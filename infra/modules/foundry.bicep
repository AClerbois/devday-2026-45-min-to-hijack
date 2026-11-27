// Azure AI Foundry : ressource AIServices + projet + déploiements de modèles + filtrage + logs

param location string
param name string
param publicAccess bool
param disableLocalAuth bool
param deploymentSku string
param modelName string
param modelVersion string
param modelCapacity int
param fallbackModelName string
param fallbackModelVersion string
param fallbackModelCapacity int
param enablePromptShields bool
param logAnalyticsId string

var hasFallback = !empty(fallbackModelName)
var strictPolicyName = 'devday-strict'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    allowProjectManagement: true
    // carte 01
    disableLocalAuth: disableLocalAuth
    // carte 02
    publicNetworkAccess: publicAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: publicAccess ? 'Allow' : 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Azure refuse deux opérations en même temps sur un même compte Foundry (« RequestConflict ») :
// ses enfants se créent l'un après l'autre. Projet → politique (06) → modèle → repli (04) → diagnostic.
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: 'devday-chaos'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'DevDay 2026 · 60 minutes chrono'
    description: 'Assistant IA de la session, saboté par le public.'
  }
}

// ---------------------------------------------------------------- carte 06
// La politique par défaut (Microsoft.DefaultV2) bloque déjà les jailbreaks grossiers.
// La politique stricte ajoute les attaques indirectes et baisse les seuils.
resource strictPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2025-06-01' = if (enablePromptShields) {
  parent: foundry
  name: strictPolicyName
  dependsOn: [
    project
  ]
  properties: {
    basePolicyName: 'Microsoft.DefaultV2'
    mode: 'Blocking'
    contentFilters: [
      { name: 'Jailbreak', enabled: true, blocking: true, source: 'Prompt' }
      { name: 'Indirect Attack', enabled: true, blocking: true, source: 'Prompt' }
      { name: 'Hate', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Prompt' }
      { name: 'Hate', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Completion' }
      { name: 'Sexual', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Prompt' }
      { name: 'Sexual', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Completion' }
      { name: 'Violence', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Prompt' }
      { name: 'Violence', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Completion' }
      { name: 'Selfharm', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Prompt' }
      { name: 'Selfharm', enabled: true, blocking: true, severityThreshold: 'Low', source: 'Completion' }
      { name: 'Protected Material Text', enabled: true, blocking: true, source: 'Completion' }
    ]
  }
}

// ---------------------------------------------------------------- cartes 04 et 05
resource primary 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelName
  dependsOn: [
    project
    strictPolicy
  ]
  sku: {
    name: deploymentSku
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: enablePromptShields ? strictPolicyName : 'Microsoft.DefaultV2'
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource fallback 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (hasFallback) {
  parent: foundry
  name: hasFallback ? fallbackModelName : 'none'
  dependsOn: [
    primary
  ]
  sku: {
    name: deploymentSku
    capacity: fallbackModelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: fallbackModelName
      version: fallbackModelVersion
    }
    raiPolicyName: enablePromptShields ? strictPolicyName : 'Microsoft.DefaultV2'
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

// ---------------------------------------------------------------- carte 07 : qui a appelé quoi
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: foundry
  name: 'to-log-analytics'
  dependsOn: [
    primary
    fallback
  ]
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output id string = foundry.id
output name string = foundry.name
output openAiEndpoint string = 'https://${name}.openai.azure.com/'
output projectName string = project.name
