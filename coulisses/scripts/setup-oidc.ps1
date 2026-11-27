#Requires -Version 7.3
# À lancer UNE FOIS avant les répétitions, connecté avec un compte admin de la souscription de démo.
# Crée l'identité du pipeline GitHub Actions (OIDC, sans secret) et ses droits.
#
# usage : ./coulisses/scripts/setup-oidc.ps1 <owner/repo> <subscription-id> [-AppId <appId>]
# Relançable : ce qui existe déjà (application, credentials, rôles, LOCATION) est réutilisé, pas recréé.
param(
    [Parameter(Mandatory, Position = 0, HelpMessage = 'owner/repo')]
    [string]$Repo,
    [Parameter(Mandatory, Position = 1, HelpMessage = 'subscription-id')]
    [string]$Sub,
    # Pour viser une application précise (sinon : celle nommée gh-devday-chaos, créée si absente)
    [string]$AppId
)

$ErrorActionPreference = 'Stop'
# Équivalent de « set -e » pour az / gh : un code de sortie non nul arrête le script
$PSNativeCommandUseErrorActionPreference = $true

$Name = 'gh-devday-chaos'

az account set --subscription $Sub
$Tenant = az account show --query tenantId -o tsv

# Relançable sans risque : on réutilise ce qui existe (sinon « az ad app create » crée un doublon du même nom)
if (-not $AppId) {
    $existing = @(az ad app list --display-name $Name --query '[].appId' -o tsv)
    if ($existing.Count -gt 1) {
        throw "Plusieurs applications « $Name » : relancer avec -AppId <celle de AZURE_CLIENT_ID> ($($existing -join ', '))"
    }
    $AppId = $existing.Count -eq 1 ? $existing[0] : (az ad app create --display-name $Name --query appId -o tsv)
}
Write-Host "Application : $AppId"

$SpId = az ad sp list --filter "appId eq '$AppId'" --query '[0].id' -o tsv
if (-not $SpId) { $SpId = az ad sp create --id $AppId --query id -o tsv }

# Confiance OIDC : seuls l'environnement « demo » (déploiement) et les PR (what-if) de ce repo peuvent se connecter
# Le JSON passe par un fichier temporaire : PowerShell casse les guillemets des arguments JSON passés à az.
$ExistingSubjects = @(az ad app federated-credential list --id $AppId --query '[].subject' -o tsv)
function New-FederatedCredential([string]$CredName, [string]$Subject) {
    if ($Subject -in $ExistingSubjects) { Write-Host "  déjà là : $Subject"; return }
    $tmp = New-TemporaryFile
    try {
        @{
            name      = $CredName
            issuer    = 'https://token.actions.githubusercontent.com'
            subject   = $Subject
            audiences = @('api://AzureADTokenExchange')
        } | ConvertTo-Json | Set-Content -Path $tmp -Encoding utf8NoBOM
        az ad app federated-credential create --id $AppId --parameters "@$tmp" -o none
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}
# GitHub peut émettre le sujet sous deux formes : « repo:owner/repo:... » (historique)
# ou « repo:owner@<id>/repo@<id>:... » (identifiants immuables). On enregistre les deux.
$Owner, $RepoName = $Repo -split '/'
$OwnerId = gh api "repos/$Repo" --jq '.owner.id'
$RepoId  = gh api "repos/$Repo" --jq '.id'
$RepoWithIds = "${Owner}@${OwnerId}/${RepoName}@${RepoId}"

New-FederatedCredential 'env-demo'          "repo:${Repo}:environment:demo"
New-FederatedCredential 'pull-requests'     "repo:${Repo}:pull_request"
New-FederatedCredential 'env-demo-ids'      "repo:${RepoWithIds}:environment:demo"
New-FederatedCredential 'pull-requests-ids' "repo:${RepoWithIds}:pull_request"

# Droits : créer les ressources, et attribuer le rôle de la Web App sur Foundry.
# Carte 07 : Mario peut pointer que « RBAC Administrator » sur la souscription est large.
# Amélioration possible : le restreindre par condition au seul rôle « Cognitive Services OpenAI User ».
foreach ($role in 'Contributor', 'Role Based Access Control Administrator') {
    $has = az role assignment list --assignee $SpId --role $role --scope "/subscriptions/$Sub" --query '[0].id' -o tsv
    if ($has) { Write-Host "  déjà là : $role"; continue }
    az role assignment create --assignee-object-id $SpId --assignee-principal-type ServicePrincipal `
        --role $role --scope "/subscriptions/$Sub" -o none
}

# Secrets et variable du repo (identifiants publics, aucun mot de passe)
gh secret set AZURE_CLIENT_ID       --repo $Repo --body $AppId
gh secret set AZURE_TENANT_ID       --repo $Repo --body $Tenant
gh secret set AZURE_SUBSCRIPTION_ID --repo $Repo --body $Sub
# Ne pas écraser LOCATION s'il existe : la carte 03 a pu le passer à francecentral
$names = @(gh variable list --repo $Repo --json name --jq '.[].name')
if ('LOCATION' -notin $names) { gh variable set LOCATION --repo $Repo --body 'swedencentral' }

Write-Host "OK. Créez l'environnement « demo » dans Settings > Environments du repo, sans reviewer obligatoire."
