// Logs et télémétrie : utiles pour les cartes 04 (voir les 429), 05 (rétention) et 07 (audit)

param location string
param name string
param retentionDays int

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${name}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${name}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

output workspaceId string = workspace.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
