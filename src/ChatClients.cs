using System.ClientModel;
using System.ClientModel.Primitives;
using Azure.AI.OpenAI;
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
        // d'attendre les tentatives du client Azure (qui respectent un délai pouvant dépasser 30 s).
        return new FallbackChatClient(
            BuildOne(o, o.Model!, retryOn429: false),
            BuildOne(o, o.FallbackModel!, retryOn429: true));
    }

    static IChatClient BuildOne(AiOptions o, string model, bool retryOn429)
    {
        var endpoint = new Uri(o.Endpoint!);

        // Foundry Local : endpoint compatible OpenAI, sans authentification
        if (o.IsLocal)
            return new OpenAIClient(new ApiKeyCredential("local"), new OpenAIClientOptions { Endpoint = endpoint })
                .GetChatClient(model)
                .AsIChatClient();

        var clientOptions = new AzureOpenAIClientOptions
        {
            RetryPolicy = new ClientRetryPolicy(maxRetries: retryOn429 ? 2 : 0),
            NetworkTimeout = TimeSpan.FromSeconds(30),
        };

        AzureOpenAIClient azure;
        if (o.UsesIdentity)
        {
            azure = new AzureOpenAIClient(endpoint, new DefaultAzureCredential(), clientOptions);
        }
        else
        {
            if (string.IsNullOrWhiteSpace(o.Key))
                throw new InvalidOperationException("Ai:Auth vaut key mais Ai:Key est vide.");
            azure = new AzureOpenAIClient(endpoint, new ApiKeyCredential(o.Key), clientOptions);
        }

        return azure.GetChatClient(model).AsIChatClient();
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
}
