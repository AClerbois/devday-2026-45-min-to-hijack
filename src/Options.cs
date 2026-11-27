namespace DevDayChaos;

// Réglages lus à chaque requête (IOptionsMonitor) : un changement d'app setting
// s'applique sans redéployer le code.

sealed class AiOptions
{
    /// <summary>azure (par défaut) ou local (Foundry Local, endpoint compatible OpenAI).</summary>
    public string Mode { get; set; } = "azure";

    /// <summary>Endpoint du modèle. Posé par le Bicep en Azure, par une variable d'environnement en local.</summary>
    public string? Endpoint { get; set; }

    /// <summary>Nom du déploiement principal.</summary>
    public string? Model { get; set; }

    /// <summary>key : utilise Key. identity : identité managée (DefaultAzureCredential), sans clé.</summary>
    public string Auth { get; set; } = "key";

    /// <summary>Clé API, utilisée seulement quand Auth = key.</summary>
    public string? Key { get; set; }

    /// <summary>Modèle de secours, utilisé quand le principal répond 429. Vide = aucun.</summary>
    public string? FallbackModel { get; set; }

    public bool UsesIdentity => string.Equals(Auth, "identity", StringComparison.OrdinalIgnoreCase);
    public bool IsLocal => string.Equals(Mode, "local", StringComparison.OrdinalIgnoreCase);
}

sealed class FeatureOptions
{
    /// <summary>Limite de questions par utilisateur (en-tête X-User), jamais par adresse IP.</summary>
    public bool RateLimit { get; set; }

    /// <summary>Prompt système durci et filtre de sortie.</summary>
    public bool PromptGuard { get; set; }

    /// <summary>Export de l'historique.</summary>
    public bool Export { get; set; } = true;
}
