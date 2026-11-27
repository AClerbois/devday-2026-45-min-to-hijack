// Carte 02 : réseau privé, déployé seulement quand enablePrivate = true

param location string
param name string

// Une ressource Foundry répond sur trois noms de domaine : il faut les trois zones privées
var zoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${name}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'app'
        properties: {
          addressPrefix: '10.40.1.0/24'
          delegations: [
            {
              name: 'web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.40.2.0/24'
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in zoneNames: {
  name: zone
  location: 'global'
}]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zone, i) in zoneNames: {
  parent: zones[i]
  name: 'link-${name}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

output appSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app')
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'private-endpoints')
output dnsZoneIds array = [for (zone, i) in zoneNames: zones[i].id]
