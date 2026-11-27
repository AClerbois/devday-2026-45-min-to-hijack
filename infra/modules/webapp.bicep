// Web App : App Service Linux, .NET, identité managée, déploiement du code (pas de conteneur)

param location string
param name string
param sku string
@description('Sous-réseau d\'intégration VNet (carte 02). Vide = pas d\'intégration.')
param appSubnetId string
param foundryName string
param aiEndpoint string
param modelName string
param fallbackModelName string
@description('Carte 01 : « key » (le piège du build) ou « identity » (identité managée).')
@allowed(['key', 'identity'])
param aiAuth string
param appInsightsConnectionString string
param featureFlags object

var integrated = !empty(appSubnetId)

// Rôle « Cognitive Services OpenAI User »
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${name}'
  location: location
  kind: 'linux'
  sku: {
    name: sku
  }
  properties: {
    reserved: true
  }
}

var baseSettings = [
  { name: 'Ai__Mode', value: 'azure' }
  { name: 'Ai__Endpoint', value: aiEndpoint }
  { name: 'Ai__Model', value: modelName }
  { name: 'Ai__FallbackModel', value: fallbackModelName }
  { name: 'Ai__Auth', value: aiAuth }
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
]

// Carte 01, le piège : en mode clé, l'app reçoit la clé du Foundry DE SA RÉGION en app setting.
// La clé commitée dans src/appsettings.json sert l'histoire de la fuite, mais elle ne vaut que pour le
// premier Foundry suédois : sans ce réglage, l'app tomberait en France (carte 03) et après chaque remise à zéro.
// En mode identité, le réglage disparaît : plus aucune clé, ni dans le code ni dans la config.
var keySettings = aiAuth == 'key' ? [
  { name: 'Ai__Key', value: foundry.listKeys().key1 }
] : []

// Un interrupteur par fonctionnalité : RateLimit (carte 04), PromptGuard (carte 06), Export (carte 08)
var flagSettings = [for flag in items(featureFlags): {
  name: 'Features__${flag.key}'
  value: string(flag.value)
}]

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    // carte 02 : le front reste public, la sortie passe par le VNet
    publicNetworkAccess: 'Enabled'
    virtualNetworkSubnetId: integrated ? appSubnetId : null
    vnetRouteAllEnabled: integrated
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat(baseSettings, keySettings, flagSettings)
    }
  }
}

// Pas d'identifiants de publication : seul le pipeline (OIDC) déploie
resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: site
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: site
  name: 'ftp'
  properties: {
    allow: false
  }
}

// carte 01 : créé dès le build, car la propagation RBAC prend plusieurs minutes
resource openAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, site.id, openAiUserRoleId)
  properties: {
    principalId: site.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
  }
}

output name string = site.name
output url string = 'https://${site.properties.defaultHostName}'
output principalId string = site.identity.principalId
