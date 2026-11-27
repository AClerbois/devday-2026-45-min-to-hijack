// Carte 02 : private endpoint de la ressource Foundry, enregistré dans les zones DNS privées

param location string
param name string
param subnetId string
param targetId string
param dnsZoneIds array

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry'
        properties: {
          privateLinkServiceId: targetId
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in dnsZoneIds: {
      name: 'zone-${i}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}
