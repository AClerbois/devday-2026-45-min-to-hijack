using System.ClientModel;
using System.ClientModel.Primitives;
using System.Runtime.CompilerServices;
using Azure.Identity;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;
using OpenAI;

namespace DevDayChaos;

// Le seul endroit qui sait OÙ tourne le modèle et COMMENT s'y authentifier.
// Le reste de l'app ne connaît qu'IChatClient.
// Le client est reconstruit dès que les réglages Ai:* changent.
sealed class ChatClientProvider(IOptionsMonitor<AiOptions> options)
{
    readonly object _lock = new();
    string? _signature;
    IChatClient? _client;

    public IChatClient Current
    {
        get
        {
            var o = options.CurrentValue;
            var signature = string.Join('|', o.Mode, o.Endpoint, o.Model, o.Auth, o.FallbackModel, o.Key?.GetHashCode());
            lock (_lock)
            {
                if (_client is null || signature != _signature)
                {
                    _client = Build(o);
                    _signature = signature;
                }
                return _client;
            }
        }
    }

    static IChatClient Build(AiOptions o)
    {
        if (string.IsNullOrWhiteSpace(o.Endpoint) || string.IsNullOrWhiteSpace(o.Model))
            throw new InvalidOperationException("Ai:Endpoint et Ai:Model doivent être renseignés.");

        if (string.IsNullOrWhiteSpace(o.FallbackModel))
            return BuildOne(o, o.Model!, retryOn429: true);

        // Avec un repli, le principal ne réessaie pas : sur un 429, on bascule tout de suite au lieu
        // d'attendre les nouvelles tentatives du client (qui respectent un délai pouvant dépasser 30 s).
        return new FallbackChatClient(
            BuildOne(o, o.Model!, retryOn429: false),
            BuildOne(o, o.FallbackModel!, retryOn429: true));
    }

    static IChatClient BuildOne(AiOptions o, string model, bool retryOn429)
    {
        // Foundry Local : endpoint compatible OpenAI, sans authentification
        if (o.IsLocal)
            return new OpenAIClient(new ApiKeyCredential("local"), new OpenAIClientOptions { Endpoint = new Uri(o.Endpoint!) })
                .GetChatClient(model)
                .AsIChatClient();

        // Foundry : l'API v1, compatible OpenAI (https://<ressource>.openai.azure.com/openai/v1/), avec le SDK OpenAI.
        // Pas d'Azure.AI.OpenAI : ses versions récentes cassent à l'exécution avec le SDK OpenAI tiré par Microsoft.Extensions.AI.
        var clientOptions = new OpenAIClientOptions
        {
            Endpoint = new Uri(o.Endpoint!.TrimEnd('/') + "/openai/v1/"),
            RetryPolicy = new ClientRetryPolicy(maxRetries: retryOn429 ? 2 : 0),
            NetworkTimeout = TimeSpan.FromSeconds(30),
        };

        OpenAIClient client;
        if (o.UsesIdentity)
        {
            // Carte 01 : identité managée, jeton Entra ID, aucune clé
            var token = new BearerTokenPolicy(new DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default");
            client = new OpenAIClient(token, clientOptions);
        }
        else
        {
            if (string.IsNullOrWhiteSpace(o.Key))
                throw new InvalidOperationException("Ai:Auth vaut key mais Ai:Key est vide.");
            client = new OpenAIClient(new ApiKeyCredential(o.Key), clientOptions);
        }

        return client.GetChatClient(model).AsIChatClient();
    }
}

// Bascule sur le modèle de secours quand le principal répond 429.
// Le principal est construit sans nouvelle tentative (voir Build) : la bascule est immédiate.
sealed class FallbackChatClient(IChatClient primary, IChatClient fallback) : DelegatingChatClient(primary)
{
    public override async Task<ChatResponse> GetResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default)
    {
        try
        {
            return await base.GetResponseAsync(messages, options, cancellationToken);
        }
        catch (ClientResultException ex) when (ex.Status == 429)
        {
            return await fallback.GetResponseAsync(messages, options, cancellationToken);
        }
    }

    // En streaming, le 429 arrive au premier élément : la bascule se fait avant d'avoir rien affiché.
    public override async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var updates = base.GetStreamingResponseAsync(messages, options, cancellationToken).GetAsyncEnumerator(cancellationToken);
        bool more;
        try
        {
            more = await updates.MoveNextAsync();
        }
        catch (ClientResultException ex) when (ex.Status == 429)
        {
            await updates.DisposeAsync();
            updates = fallback.GetStreamingResponseAsync(messages, options, cancellationToken).GetAsyncEnumerator(cancellationToken);
            more = await updates.MoveNextAsync();
        }

        try
        {
            while (more)
            {
                yield return updates.Current;
                more = await updates.MoveNextAsync();
            }
        }
        finally
        {
            await updates.DisposeAsync();
        }
    }
}
