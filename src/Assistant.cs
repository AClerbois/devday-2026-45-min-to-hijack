using System.ClientModel;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace DevDayChaos;

// Une réponse et le code HTTP qui va avec (l'API le renvoie, l'UI n'affiche que le texte)
sealed record Answer(int Status, string Text);

// L'assistant du DevDay : le même chemin pour la page Blazor et pour POST /api/chat.
// Limite par spectateur (carte 04), prompt durci et filtre de sortie (carte 06), historique (carte 08) :
// tout passe ici, quelle que soit la porte d'entrée.
sealed class DevDayAssistant(
    ChatClientProvider clients,
    IOptionsMonitor<FeatureOptions> features,
    QuestionLimiter limiter,
    ConversationLog log,
    ILogger<DevDayAssistant> logger)
{
    public const int MaxQuestionLength = 500;

    // Le chat envoie toute la conversation ; on n'en garde que la fin. Chaque message ajouté
    // compte dans le quota du modèle (carte 04) : 4 messages = la question et les deux tours précédents.
    const int HistoryMessages = 4;

    // Le filtre de contenu côté réponse peut rendre une réponse vide, sans erreur
    const string EmptyAnswer = "Bien essayé. Les garde-fous ont retiré la réponse.";

    // Azure compte MaxOutputTokens dans le quota de chaque requête, même si la réponse est courte :
    // 300 tokens laissent passer plusieurs fois plus de questions par minute qu'avec 1 000.
    static ChatOptions NewOptions() => new() { MaxOutputTokens = 300, Temperature = 0.2f };

    // ------------------------------------------------------------ API : une question, une réponse
    public async Task<Answer> AskAsync(string? question, string? user, CancellationToken ct = default)
    {
        var (prepared, refusal) = Prepare([new ChatMessage(ChatRole.User, question ?? "")], user);
        return refusal ?? await AnswerOnceAsync(prepared!, catchAll: false, ct);
    }

    // ------------------------------------------------------------ UI : la réponse arrive au fil de l'eau
    public async IAsyncEnumerable<string> StreamAsync(
        IEnumerable<ChatMessage> conversation, string? user, [EnumeratorCancellation] CancellationToken ct = default)
    {
        var (prepared, refusal) = Prepare(conversation, user);
        if (refusal is not null)
        {
            yield return refusal.Text;
            yield break;
        }

        // Carte 06 : le filtre de sortie doit voir la réponse entière avant de la montrer,
        // sinon le canari aurait déjà défilé à l'écran. Prompt durci = pas de streaming.
        if (prepared!.Guard)
        {
            yield return (await AnswerOnceAsync(prepared, catchAll: true, ct)).Text;
            yield break;
        }

        var text = new StringBuilder();
        string? failure = null;
        IAsyncEnumerator<ChatResponseUpdate>? updates = null;
        try
        {
            while (true)
            {
                // Pas de yield dans un try/catch en C# : on lit dans le try, on rend le morceau en dehors
                string? chunk = null;
                try
                {
                    updates ??= clients.Current.GetStreamingResponseAsync(prepared.Messages, NewOptions(), ct).GetAsyncEnumerator(ct);
                    if (!await updates.MoveNextAsync())
                        break;
                    chunk = updates.Current.Text;
                }
                catch (Exception ex) when (Explain(ex, catchAll: true) is { } explained)
                {
                    failure = explained.Text;
                    break;
                }

                if (!string.IsNullOrEmpty(chunk))
                {
                    text.Append(chunk);
                    yield return chunk;
                }
            }
        }
        finally
        {
            if (updates is not null)
                await updates.DisposeAsync();
        }

        if (failure is not null)
        {
            yield return text.Length > 0 ? $"\n\n{failure}" : failure;
        }
        else if (text.Length == 0)
        {
            yield return EmptyAnswer;
            log.Add(prepared.Question, EmptyAnswer);
        }
        else
        {
            log.Add(prepared.Question, text.ToString());
        }
    }

    // ------------------------------------------------------------ commun
    sealed record Prepared(List<ChatMessage> Messages, string Question, bool Guard);

    (Prepared? Ready, Answer? Refusal) Prepare(IEnumerable<ChatMessage> conversation, string? user)
    {
        // Seulement le texte des échanges : ni les messages système venus d'ailleurs, ni les contenus d'affichage du chat
        var history = conversation
            .Where(m => m.Role == ChatRole.User || m.Role == ChatRole.Assistant)
            .Select(m => new ChatMessage(m.Role, m.Text))
            .TakeLast(HistoryMessages)
            .ToList();

        var question = history.Count > 0 && history[^1].Role == ChatRole.User ? history[^1].Text : "";
        if (string.IsNullOrWhiteSpace(question) || question.Length > MaxQuestionLength)
            return (null, new Answer(StatusCodes.Status400BadRequest, "Une question de 500 caractères maximum, s'il vous plaît."));

        // Carte 04 : par spectateur, jamais par adresse IP (toute la salle partage le Wi-Fi).
        // Sans identifiant de spectateur, pas de limite : à faire relever par Mario.
        var f = features.CurrentValue;
        if (f.RateLimit && !string.IsNullOrEmpty(user) && !limiter.TryAcquire(user))
            return (null, new Answer(StatusCodes.Status429TooManyRequests, "Limite atteinte : 5 questions par minute. Réessayez dans un instant."));

        history.Insert(0, new ChatMessage(ChatRole.System, f.PromptGuard ? Prompts.Hardened : Prompts.Default));
        return (new Prepared(history, question, f.PromptGuard), null);
    }

    async Task<Answer> AnswerOnceAsync(Prepared prepared, bool catchAll, CancellationToken ct)
    {
        try
        {
            var response = await clients.Current.GetResponseAsync(prepared.Messages, NewOptions(), ct);
            var answer = prepared.Guard ? Guard.Check(response.Text) : response.Text;
            if (string.IsNullOrWhiteSpace(answer))
                answer = EmptyAnswer;
            log.Add(prepared.Question, answer);
            return new Answer(StatusCodes.Status200OK, answer);
        }
        catch (Exception ex) when (Explain(ex, catchAll) is { } explained)
        {
            return explained;
        }
    }

    // Les pannes que les cartes provoquent, dites en clair. catchAll : l'UI affiche toujours quelque chose,
    // l'API laisse remonter l'inattendu (500), comme avant.
    Answer? Explain(Exception ex, bool catchAll)
    {
        switch (ex)
        {
            case ClientResultException { Status: 429 }:
                return new Answer(StatusCodes.Status429TooManyRequests, "Quota du modèle épuisé. Réessayez dans un instant.");
            case ClientResultException { Status: 400 }:
                // Le filtrage de contenu de Foundry a refusé la question ou la réponse
                return new Answer(StatusCodes.Status200OK, "Bien essayé. Les garde-fous ont refusé la question.");
            case ClientResultException { Status: 401 or 403 }:
                return new Answer(StatusCodes.Status502BadGateway, "Le modèle refuse l'authentification.");
            case InvalidOperationException:
                return new Answer(StatusCodes.Status500InternalServerError, $"Configuration incomplète : {ex.Message}");
            case OperationCanceledException:
                return null;
        }

        if (!catchAll)
            return null;
        logger.LogError(ex, "Le modèle n'a pas répondu");
        return new Answer(StatusCodes.Status502BadGateway, "Le modèle ne répond pas pour le moment.");
    }
}

// Carte 04 : 5 questions par minute et par spectateur, décidé à chaque question selon Features:RateLimit
sealed class QuestionLimiter : IDisposable
{
    readonly PartitionedRateLimiter<string> _limiter = PartitionedRateLimiter.Create<string, string>(user =>
        RateLimitPartition.GetFixedWindowLimiter(user, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 5,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        }));

    public bool TryAcquire(string user)
    {
        using var lease = _limiter.AttemptAcquire(user);
        return lease.IsAcquired;
    }

    public void Dispose() => _limiter.Dispose();
}

// Ce que voit le chat Blazor : un IChatClient. Derrière, l'assistant et toutes les parades des cartes.
// Un par onglet ouvert, avec l'identifiant du spectateur.
sealed class AssistantChatClient(DevDayAssistant assistant, string? visitorId) : IChatClient
{
    public async Task<ChatResponse> GetResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default)
    {
        var text = new StringBuilder();
        await foreach (var chunk in assistant.StreamAsync(messages, visitorId, cancellationToken))
            text.Append(chunk);
        return new ChatResponse(new ChatMessage(ChatRole.Assistant, text.ToString()));
    }

    public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        // Le même identifiant sur tous les morceaux : le chat les assemble en un seul message
        var messageId = Guid.NewGuid().ToString("N");
        await foreach (var chunk in assistant.StreamAsync(messages, visitorId, cancellationToken))
            yield return new ChatResponseUpdate(ChatRole.Assistant, chunk) { MessageId = messageId };
    }

    public object? GetService(Type serviceType, object? serviceKey = null) =>
        serviceKey is null && serviceType.IsInstanceOfType(this) ? this : null;

    public void Dispose() { }
}

// Un identifiant par navigateur, posé en cookie : la clé de la limite par spectateur dans le chat.
// (L'API, elle, lit l'en-tête X-User, comme avant.)
static class Visitor
{
    public const string ItemKey = "devday-uid";
    const string Cookie = "devday-uid";

    public static async Task Middleware(HttpContext ctx, RequestDelegate next)
    {
        if (!ctx.Request.Path.StartsWithSegments("/api"))
        {
            var uid = ctx.Request.Cookies[Cookie];
            if (string.IsNullOrEmpty(uid) || uid.Length > 64)
            {
                uid = Guid.NewGuid().ToString("N");
                ctx.Response.Cookies.Append(Cookie, uid, new CookieOptions
                {
                    HttpOnly = true,
                    Secure = ctx.Request.IsHttps,
                    SameSite = SameSiteMode.Lax,
                    IsEssential = true,
                    MaxAge = TimeSpan.FromDays(7),
                });
            }
            ctx.Items[ItemKey] = uid;
        }
        await next(ctx);
    }
}

// La configuration active : servie par /api/status et affichée par le bandeau d'état
sealed record AppStatus(
    string Mode, string Region, string? Model, string? FallbackModel, string Auth,
    bool RateLimit, bool PromptGuard, bool Export)
{
    public static AppStatus Read(AiOptions a, FeatureOptions f, IConfiguration c) => new(
        Mode: a.IsLocal ? "local" : "azure",
        Region: CurrentRegion(c),
        Model: a.Model,
        FallbackModel: string.IsNullOrWhiteSpace(a.FallbackModel) ? null : a.FallbackModel,
        Auth: a.IsLocal ? "aucune" : a.UsesIdentity ? "identité managée" : "clé API",
        RateLimit: f.RateLimit,
        PromptGuard: f.PromptGuard,
        Export: f.Export);

    // La Web App s'appelle app-devday-chaos-<région> : la région se lit dans son nom
    static string CurrentRegion(IConfiguration c)
    {
        var site = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
        var dash = site?.LastIndexOf('-') ?? -1;
        if (dash > 0)
            return site![(dash + 1)..];
        return c["Demo:Region"] ?? "local";
    }
}
