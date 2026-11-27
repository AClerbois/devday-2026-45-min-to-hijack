using System.Collections.Concurrent;
using Newtonsoft.Json;

namespace DevDayChaos;

// Historique en mémoire des dernières questions (rien n'est stocké sur disque)
sealed class ConversationLog
{
    readonly ConcurrentQueue<Entry> _entries = new();

    public void Add(string question, string answer)
    {
        _entries.Enqueue(new Entry(DateTimeOffset.UtcNow, question, answer));
        while (_entries.Count > 100 && _entries.TryDequeue(out _)) { }
    }

    public IReadOnlyList<Entry> Last(int count) => _entries.Reverse().Take(count).ToList();

    public sealed record Entry(DateTimeOffset At, string Question, string Answer);
}

// Export de l'historique en JSON. Désactivable par Features__Export=false.
static class Export
{
    public static string ToJson(IReadOnlyList<ConversationLog.Entry> entries) =>
        JsonConvert.SerializeObject(new { exportedAt = DateTimeOffset.UtcNow, entries }, Formatting.Indented);
}
