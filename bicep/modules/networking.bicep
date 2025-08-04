@description('Networking module with VNet and subnets for Function Apps')
param vnetName string
param location string = resourceGroup().location

@description('Environment (dev, test, prod)')
param environment string = 'dev'

@description('Tags for resource tagging')
param tags object = {}

@description('Virtual Network address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Number of Function App subnets to create')
param functionAppSubnetCount int = 5

@description('Subnet address prefix base (will be incremented)')
param subnetAddressPrefixBase string = '10.0.'

// Virtual Network with In Control compliance
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    enableDdosProtection: false
    enableVmProtection: false
    subnets: [
      // Shared services subnet
      {
        name: 'shared-services-subnet'
        properties: {
          addressPrefix: '${subnetAddressPrefixBase}1.0/24'
          networkSecurityGroup: {
            id: sharedServicesNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      // Gateway subnet for VPN/ExpressRoute
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '${subnetAddressPrefixBase}0.0/27'
        }
      }
    ]
  }
}

// Network Security Group for shared services
resource sharedServicesNsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${vnetName}-shared-services-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Network Security Group template for Function Apps
resource functionAppNsgTemplate 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${vnetName}-function-app-nsg-template'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowInternetOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 1001
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Create individual NSGs and subnets for each Function App
resource functionAppNsgs 'Microsoft.Network/networkSecurityGroups@2023-04-01' = [for i in range(0, functionAppSubnetCount): {
  name: '${vnetName}-function-app-${i + 1}-nsg'
  location: location
  tags: tags
  properties: functionAppNsgTemplate.properties
}]

resource functionAppSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = [for i in range(0, functionAppSubnetCount): {
  parent: vnet
  name: 'function-app-${i + 1}-subnet'
  properties: {
    addressPrefix: '${subnetAddressPrefixBase}${i + 10}.0/24'
    networkSecurityGroup: {
      id: functionAppNsgs[i].id
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
      {
        service: 'Microsoft.KeyVault'
      }
      {
        service: 'Microsoft.Sql'
      }
      {
        service: 'Microsoft.Web'
      }
    ]
    delegations: [
      {
        name: 'Microsoft.Web.serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  dependsOn: [
    functionAppNsgs[i]
  ]
}]

// Route table for custom routing (if needed)
resource routeTable 'Microsoft.Network/routeTables@2023-04-01' = {
  name: '${vnetName}-route-table'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'default-route'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}

@description('Virtual Network resource ID')
output vnetId string = vnet.id

@description('Virtual Network name')
output vnetName string = vnet.name

@description('Shared services subnet ID')
output sharedServicesSubnetId string = vnet.properties.subnets[0].id

@description('Function App subnet IDs')
output functionAppSubnetIds array = [for i in range(0, functionAppSubnetCount): functionAppSubnets[i].id]

@description('Function App subnet names')
output functionAppSubnetNames array = [for i in range(0, functionAppSubnetCount): functionAppSubnets[i].name]

@description('Network Security Group IDs for Function Apps')
output functionAppNsgIds array = [for i in range(0, functionAppSubnetCount): functionAppNsgs[i].id]
