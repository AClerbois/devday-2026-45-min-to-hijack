// Demandez au DevDay · l'assistant IA du DevDay 2026
// L'UI : Blazor (rendu interactif côté serveur) et les composants Blazor AI, expérimentaux, pour le chat.
//
// Réglages (app settings posés par infra/main.bicep, relus à chaque requête) :
//   Ai__Mode, Ai__Endpoint, Ai__Model, Ai__Auth, Ai__Key, Ai__FallbackModel
//   Features__RateLimit, Features__PromptGuard, Features__Export

using Azure.Monitor.OpenTelemetry.AspNetCore;
using DevDayChaos;
using DevDayChaos.Components;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.Configure<AiOptions>(config.GetSection("Ai"));
builder.Services.Configure<FeatureOptions>(config.GetSection("Features"));
builder.Services.AddSingleton<ChatClientProvider>();
builder.Services.AddSingleton<ConversationLog>();
builder.Services.AddSingleton<QuestionLimiter>();
builder.Services.AddSingleton<DevDayAssistant>();

builder.Services.AddRazorComponents().AddInteractiveServerComponents();

// Télémétrie vers Application Insights, quand elle est configurée
if (!string.IsNullOrEmpty(config["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
    builder.Services.AddOpenTelemetry().UseAzureMonitor();

var app = builder.Build();

app.Use(Visitor.Middleware);
app.UseAntiforgery();
app.MapStaticAssets();

// ---------------------------------------------------------------- état de la configuration
app.MapGet("/api/status", (IOptionsMonitor<AiOptions> ai, IOptionsMonitor<FeatureOptions> features, IConfiguration c) =>
    AppStatus.Read(ai.CurrentValue, features.CurrentValue, c));

// ---------------------------------------------------------------- la question au modèle
// Utilisée par le test de fumée du pipeline, les preuves de run.md et coulisses/scripts/charge.ps1.
// Limite par spectateur : l'en-tête X-User (sans lui, pas de limite).
app.MapPost("/api/chat", async (ChatRequest req, HttpRequest http, DevDayAssistant assistant, CancellationToken ct) =>
{
    var answer = await assistant.AskAsync(req.Question, http.Headers["X-User"].ToString(), ct);
    return Results.Json(new { answer = answer.Text }, statusCode: answer.Status);
});

// ---------------------------------------------------------------- export de l'historique
app.MapGet("/api/export", (IOptionsMonitor<FeatureOptions> features, ConversationLog log) =>
    features.CurrentValue.Export
        ? Results.Text(Export.ToJson(log.Last(20)), "application/json")
        : Results.Json(new { message = "Export temporairement désactivé." },
            statusCode: StatusCodes.Status503ServiceUnavailable));

// ---------------------------------------------------------------- la page
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();

app.Run();

record ChatRequest(string? Question);
