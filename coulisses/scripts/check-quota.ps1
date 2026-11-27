#Requires -Version 7.3
# À lancer AVANT le premier déploiement (et avant chaque répétition) : vérifie que la souscription a du quota
# pour les modèles de main.bicepparam, dans la région de départ ET celle de la carte 03.
#
# Il n'existe pas d'API pour DEMANDER du quota Azure OpenAI : seulement le portail Foundry (ou le formulaire
# https://aka.ms/oai/stuquotarequest). Ce script dit exactement quoi demander et ouvre le portail.
# L'approbation peut prendre plusieurs jours : le lancer tôt.
#
# usage : ./coulisses/scripts/check-quota.ps1 [-Regions swedencentral,francecentral] [-ExtraModels gpt-4.1-nano] [-Open]
param(
    [string[]]$Regions = @('swedencentral', 'francecentral'),
    # Modèles non actifs dans le bicepparam mais utilisés par une carte (carte 04 : modèle de repli)
    [string[]]$ExtraModels = @('gpt-4.1-nano'),
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# --- Ce que le Bicep va demander : valeurs par défaut de main.bicep, remplacées par celles de main.bicepparam
function Read-BicepValues([string]$Path, [string]$Pattern) {
    $values = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match $Pattern) { $values[$Matches[1]] = $Matches[2].Trim() }
    }
    $values
}
$infra    = Join-Path $PSScriptRoot '..\..\infra'
$params   = Read-BicepValues "$infra\main.bicep" "^\s*param\s+(\w+)\s+\w+\s*=\s*'?([^'/]*?)'?\s*(//.*)?$"
$override = Read-BicepValues "$infra\main.bicepparam" "^\s*param\s+(\w+)\s*=\s*'?([^'/]*?)'?\s*(//.*)?$"
foreach ($k in $override.Keys) { $params[$k] = $override[$k] }

$sku = $params['deploymentSku']

# Capacité nécessaire par modèle (en milliers de tokens par minute) : le principal, et le repli de la carte 04
$need = [ordered]@{}
$need[$params['modelName']] = [int]$params['modelCapacity']
$fallbackCapacity = [int]$params['fallbackModelCapacity']
foreach ($m in @($params['fallbackModelName']) + $ExtraModels | Where-Object { $_ } | Select-Object -Unique) {
    $need[$m] = ($need[$m] ?? 0) + $fallbackCapacity
}

Write-Host "Souscription : $(az account show --query name -o tsv)"
Write-Host "Besoin en $sku : $(($need.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value) K TPM" }) -join ' · ')`n"

# --- Quota par région. On compare à la LIMITE : un déploiement déjà en place consomme le quota qu'il occupe.
$missing = @()
foreach ($region in $Regions) {
    $usages = az cognitiveservices usage list -l $region -o json | ConvertFrom-Json
    foreach ($model in $need.Keys) {
        $u = $usages | Where-Object { $_.name.value -eq "OpenAI.$sku.$model" }
        $limit = if ($u) { [int]$u.limit } else { 0 }
        $used  = if ($u) { [int]$u.currentValue } else { 0 }
        $ok = $limit -ge $need[$model]
        $status = $ok ? 'OK   ' : 'MANQUE'
        Write-Host ("  {0}  {1,-15} {2,-14} besoin {3,3} · limite {4,3} · utilisé {5,3}" -f $status, $region, $model, $need[$model], $limit, $used) `
            -ForegroundColor ($ok ? 'Green' : 'Red')
        if (-not $ok) { $missing += [pscustomobject]@{ Region = $region; Model = $model } }
    }
}

if (-not $missing) {
    Write-Host "`nQuota suffisant partout : le déploiement peut passer." -ForegroundColor Green
    exit 0
}

# --- Quoi demander
$scope = $sku -like 'DataZone*' ? 'eur (une seule demande couvre toutes les régions UE)' : 'la région concernée'
Write-Host "`nÀ demander dans le portail Foundry : Management center > Quota > Request quota" -ForegroundColor Yellow
foreach ($model in ($missing.Model | Select-Object -Unique)) {
    Write-Host "  - Modèle $model · Type de déploiement $sku · Étendue $scope · Total target quota >= $($need[$model] * 1000) TPM"
}
Write-Host "  Abonnements Visual Studio / essai : la demande peut être refusée. Repli : https://aka.ms/oai/stuquotarequest"

if ($Open) { Start-Process 'https://ai.azure.com' }
exit 1
