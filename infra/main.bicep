// DevDay 2026 · « 60 minutes chrono » · infra de démo
// Une Web App (App Service Linux, .NET) + une ressource Azure AI Foundry (projet + modèles).
// Chaque carte chaos se joue en AJOUTANT une ligne dans main.bicepparam, puis push.
// Les valeurs par défaut ci-dessous sont l'état du build : main.bicepparam ne contient aucune parade
// (rien ne trahit les cartes s'il est projeté). Ne pas changer ces défauts : ajouter la ligne dans le bicepparam.

targetScope = 'resourceGroup'

// ---------------------------------------------------------------- général
@description('Région. Carte 03 : le pipeline la change via la variable AZ_LOCATION.')
param location string = resourceGroup().location

@description('Préfixe des noms de ressources.')
param baseName string = 'devday'

// ---------------------------------------------------------------- carte 01 · clé API fuitée
@description('Carte 01, 1er push : true = l\'app appelle Foundry avec son identité managée au lieu de la clé (app setting Ai__Auth).')
param useManagedIdentity bool = false

@description('Carte 01, 2e push : true = authentification par clé désactivée, seule l\'identité managée passe.')
param disableLocalAuth bool = false

// ---------------------------------------------------------------- carte 02 · le RSSI refuse l'accès public
@description('Carte 02 : true = Foundry en accès privé (private endpoint + DNS privé), Web App intégrée au VNet.')
param enablePrivate bool = false

// ---------------------------------------------------------------- modèles · cartes 04 et 05
@description('Modèle principal. Carte 05 : on passe à un modèle plus petit.')
param modelName string = 'gpt-4.1-mini'
param modelVersion string = '2025-04-14'

@description('Carte 04 : quota volontairement serré au build (en milliers de tokens par minute). Assez pour l\'usage normal de la salle, pas pour scripts/charge.ps1. À confirmer au dry-run.')
param modelCapacity int = 10

@description('Carte 04 : modèle de repli. Un AUTRE modèle, car le quota est compté par modèle. Vide = pas de repli.')
param fallbackModelName string = ''
param fallbackModelVersion string = ''
@description('Carte 04 : capacité du repli, assez large pour absorber charge.ps1. À confirmer au dry-run (et dans la demande de quota).')
param fallbackModelCapacity int = 50

@description('DataZoneStandard : les données restent dans la zone UE.')
param deploymentSku string = 'DataZoneStandard'

// ---------------------------------------------------------------- carte 05 · budget divisé par deux
@description('Carte 05 : P0v3 au build, B1 après la carte.')
param appSku string = 'P0v3'

@description('Carte 05 : rétention des logs en jours.')
@minValue(30)
param logRetentionDays int = 90

@description('Carte 05 : montant du budget mensuel en euros. 0 = pas de budget.')
param budgetAmount int = 0
param budgetStartDate string = '2026-12-01'
param budgetEmails array = []

// ---------------------------------------------------------------- carte 06 · injection de prompt
@description('Carte 06 : true = politique de filtrage stricte (Prompt Shields, attaques indirectes, seuils bas).')
param enablePromptShields bool = false

// ---------------------------------------------------------------- carte 07 · audit des accès
@description('Carte 07, PIÈGE du build : object id d\'un humain qui reçoit Owner sur le groupe de ressources. Vide = rien.')
param devOwnerPrincipalId string = ''

// ---------------------------------------------------------------- carte 08 · CVE zero-day
@description('Carte 08 : interrupteurs de fonctionnalités, injectés en app settings Features__<nom>.')
param featureFlags object = {
  Export: true
}

// ---------------------------------------------------------------- code de l'app : tout est livré au build, la carte l'active
// Les parades « code » des cartes 04 et 06 sont déjà dans l'app, éteintes. Elles s'allument avec le
// paramètre infra de leur carte : une seule ligne à changer, aucun merge en direct.
// featureFlags passe en dernier : il peut forcer un interrupteur à la main.
var appFeatures = union({
  RateLimit: !empty(fallbackModelName)    // carte 04 : limite par spectateur, en même temps que le modèle de repli
  PromptGuard: enablePromptShields        // carte 06 : prompt cadré et filtre de sortie, en même temps que Prompt Shields
}, featureFlags)

// Carte 01 : clés interdites sans identité managée = app en panne. disableLocalAuth force donc l'identité.
var aiAuth = useManagedIdentity || disableLocalAuth ? 'identity' : 'key'

// ---------------------------------------------------------------- noms
var suffix = take(uniqueString(resourceGroup().id), 6)
var foundryName = toLower('fdy-${baseName}-${suffix}')
// Nom lisible et prévisible (pas de suffixe aléatoire) : l'URL de chaque région est connue d'avance,
// et la région affichée dans l'adresse sert de preuve à la carte 03. Le lien court du QR code pointe dessus.
var appName = toLower('app-${baseName}-chaos-${location}')

// ---------------------------------------------------------------- modules
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    name: '${baseName}-${suffix}'
    retentionDays: logRetentionDays
  }
}

module network 'modules/network.bicep' = if (enablePrivate) {
  name: 'network'
  params: {
    location: location
    name: '${baseName}-${suffix}'
  }
}

module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    name: foundryName
    publicAccess: !enablePrivate
    disableLocalAuth: disableLocalAuth
    deploymentSku: deploymentSku
    modelName: modelName
    modelVersion: modelVersion
    modelCapacity: modelCapacity
    fallbackModelName: fallbackModelName
    fallbackModelVersion: fallbackModelVersion
    fallbackModelCapacity: fallbackModelCapacity
    enablePromptShields: enablePromptShields
    logAnalyticsId: monitoring.outputs.workspaceId
  }
}

module privateEndpoint 'modules/private-endpoint.bicep' = if (enablePrivate) {
  name: 'private-endpoint'
  params: {
    location: location
    name: 'pe-${foundryName}'
    subnetId: network!.outputs.peSubnetId
    targetId: foundry.outputs.id
    dnsZoneIds: network!.outputs.dnsZoneIds
  }
}

module webapp 'modules/webapp.bicep' = {
  name: 'webapp'
  params: {
    location: location
    name: appName
    sku: appSku
    appSubnetId: enablePrivate ? network!.outputs.appSubnetId : ''
    foundryName: foundry.outputs.name
    aiEndpoint: foundry.outputs.openAiEndpoint
    modelName: modelName
    fallbackModelName: fallbackModelName
    aiAuth: aiAuth
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    featureFlags: appFeatures
  }
}

// ---------------------------------------------------------------- carte 07 · le piège
var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

resource devOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(devOwnerPrincipalId)) {
  name: guid(resourceGroup().id, devOwnerPrincipalId, ownerRoleId)
  properties: {
    principalId: devOwnerPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleId)
  }
}

// ---------------------------------------------------------------- carte 05 · budget
resource budget 'Microsoft.Consumption/budgets@2023-11-01' = if (budgetAmount > 0) {
  name: 'budget-${baseName}-${suffix}'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      reel80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: budgetEmails
      }
      prevu100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: budgetEmails
      }
    }
  }
}

// ---------------------------------------------------------------- sorties
output appName string = webapp.outputs.name
output appUrl string = webapp.outputs.url
output foundryName string = foundry.outputs.name
output aiEndpoint string = foundry.outputs.openAiEndpoint
