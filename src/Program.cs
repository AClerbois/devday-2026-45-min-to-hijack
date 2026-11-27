// Demandez au DevDay · l'assistant IA du DevDay 2026
//
// Réglages (app settings posés par infra/main.bicep, relus à chaque requête) :
//   Ai__Mode, Ai__Endpoint, Ai__Model, Ai__Auth, Ai__Key, Ai__FallbackModel
//   Features__RateLimit, Features__PromptGuard, Features__Export

using System.ClientModel;
using System.Threading.RateLimiting;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using DevDayChaos;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.Configure<AiOptions>(config.GetSection("Ai"));
builder.Services.Configure<FeatureOptions>(config.GetSection("Features"));
builder.Services.AddSingleton<ChatClientProvider>();
builder.Services.AddSingleton<ConversationLog>();

// Télémétrie vers Application Insights, quand elle est configurée
if (!string.IsNullOrEmpty(config["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
    builder.Services.AddOpenTelemetry().UseAzureMonitor();

// Limite par utilisateur, décidée à chaque requête selon Features:RateLimit.
// Clé de partition : l'en-tête X-User (un identifiant par navigateur), jamais l'adresse IP :
// toute une salle partage la même IP de Wi-Fi.
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy(RateLimits.PerUser, ctx =>
    {
        var features = ctx.RequestServices.GetRequiredService<IOptionsMonitor<FeatureOptions>>().CurrentValue;
        var user = ctx.Request.Headers["X-User"].ToString();
        return features.RateLimit && user.Length > 0
            ? RateLimitPartition.GetFixedWindowLimiter(user,
                _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(1) })
            : RateLimitPartition.GetNoLimiter("sans-limite");
    });
});

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();
app.UseRateLimiter();

// ---------------------------------------------------------------- état de la configuration
app.MapGet("/api/status", (IOptionsMonitor<AiOptions> ai, IOptionsMonitor<FeatureOptions> features, IConfiguration c) =>
{
    var a = ai.CurrentValue;
    var f = features.CurrentValue;
    return new
    {
        mode = a.IsLocal ? "local" : "azure",
        region = Region.Current(c),
        model = a.Model,
        fallbackModel = string.IsNullOrWhiteSpace(a.FallbackModel) ? null : a.FallbackModel,
        auth = a.IsLocal ? "aucune" : a.UsesIdentity ? "identité managée" : "clé API",
        rateLimit = f.RateLimit,
        promptGuard = f.PromptGuard,
        export = f.Export,
    };
});

// ---------------------------------------------------------------- la question au modèle
app.MapPost("/api/chat", async (ChatRequest req, ChatClientProvider clients,
    IOptionsMonitor<FeatureOptions> features, ConversationLog log) =>
{
    if (string.IsNullOrWhiteSpace(req.Question) || req.Question.Length > 500)
        return Results.BadRequest(new { answer = "Une question de 500 caractères maximum, s'il vous plaît." });

    var guard = features.CurrentValue.PromptGuard;
    try
    {
        var messages = new List<ChatMessage>
        {
            new(ChatRole.System, guard ? Prompts.Hardened : Prompts.Default),
            new(ChatRole.User, req.Question),
        };
        // Azure compte MaxOutputTokens dans le quota de chaque requête, même si la réponse est courte :
        // 300 tokens laissent passer plusieurs fois plus de questions par minute qu'avec 1 000.
        var options = new ChatOptions
        {
            MaxOutputTokens = 300,
            Temperature = 0.2f,
        };

        var response = await clients.Current.GetResponseAsync(messages, options);
        var answer = guard ? Guard.Check(response.Text) : response.Text;

        log.Add(req.Question, answer);
        return Results.Ok(new { answer });
    }
    catch (ClientResultException ex) when (ex.Status == 429)
    {
        return Results.Json(new { answer = "Quota du modèle épuisé. Réessayez dans un instant." },
            statusCode: StatusCodes.Status429TooManyRequests);
    }
    catch (ClientResultException ex) when (ex.Status == 400)
    {
        // Le filtrage de contenu de Foundry a refusé la question ou la réponse
        return Results.Ok(new { answer = "Bien essayé. Les garde-fous ont refusé la question." });
    }
    catch (ClientResultException ex) when (ex.Status is 401 or 403)
    {
        return Results.Json(new { answer = "Le modèle refuse l'authentification." },
            statusCode: StatusCodes.Status502BadGateway);
    }
    catch (InvalidOperationException ex)
    {
        return Results.Json(new { answer = $"Configuration incomplète : {ex.Message}" },
            statusCode: StatusCodes.Status500InternalServerError);
    }
}).RequireRateLimiting(RateLimits.PerUser);

// ---------------------------------------------------------------- export de l'historique
app.MapGet("/api/export", (IOptionsMonitor<FeatureOptions> features, ConversationLog log) =>
    features.CurrentValue.Export
        ? Results.Text(Export.ToJson(log.Last(20)), "application/json")
        : Results.Json(new { message = "Export temporairement désactivé." },
            statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();

record ChatRequest(string Question);

static class RateLimits
{
    public const string PerUser = "parUtilisateur";
}

static class Region
{
    // La Web App s'appelle app-devday-chaos-<région> : la région se lit dans son nom
    public static string Current(IConfiguration c)
    {
        var site = Environment.GetEnvironmentVariable("WEBSITE_SITE_NAME");
        var dash = site?.LastIndexOf('-') ?? -1;
        if (dash > 0)
            return site![(dash + 1)..];
        return c["Demo:Region"] ?? "local";
    }
}
