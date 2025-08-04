@description('Main Bicep template for BOIHub Function App infrastructure')
targetScope = 'resourceGroup'

// Parameters
@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Project name prefix')
param projectName string = 'boihub'

@description('Function App configurations')
param functionApps array = [
  {
    name: 'webparts-api'
    runtime: 'dotnet'
    runtimeVersion: '6'
  }
  {
    name: 'data-processor'
    runtime: 'dotnet'
    runtimeVersion: '6'
  }
]

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('App Service Plan SKU')
param appServicePlanSku object = {
  name: 'Y1'
  tier: 'Dynamic'
}

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  ManagedBy: 'Bicep'
  Owner: 'BOIHub-DevOps'
}

// Variables
var resourcePrefix = '${projectName}-${environment}'
var vnetName = '${resourcePrefix}-vnet'
var storageAccountName = replace('${resourcePrefix}storage', '-', '')
var appInsightsName = '${resourcePrefix}-appinsights'
var logAnalyticsName = '${resourcePrefix}-logs'
var appServicePlanName = '${resourcePrefix}-asp'
var keyVaultName = '${resourcePrefix}-kv'

// Networking module
module networking 'modules/networking.bicep' = {
  name: 'networking-deployment'
  params: {
    vnetName: vnetName
    location: location
    environment: environment
    tags: tags
    functionAppSubnetCount: length(functionApps)
    vnetAddressPrefix: '10.0.0.0/16'
    subnetAddressPrefixBase: '10.0.'
  }
}

// Storage Account module
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    environment: environment
    tags: tags
    skuName: storageAccountSku
  }
}

// Application Insights module
module appInsights 'modules/app-insights.bicep' = {
  name: 'appinsights-deployment'
  params: {
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceName: logAnalyticsName
    location: location
    environment: environment
    tags: tags
    retentionInDays: environment == 'prod' ? 180 : 90
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: false
    // In Control compliance
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
  }
}

// App Service Plan for Function Apps
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: appServicePlanSku
  kind: 'functionapp'
  properties: {
    reserved: false
  }
}

// Function Apps deployment
module functionAppDeployments 'modules/function-app.bicep' = [for (functionApp, index) in functionApps: {
  name: '${functionApp.name}-deployment'
  params: {
    functionAppName: '${resourcePrefix}-${functionApp.name}'
    location: location
    appServicePlanId: appServicePlan.id
    storageAccountName: storage.outputs.storageAccountName
    applicationInsightsKey: appInsights.outputs.instrumentationKey
    subnetId: networking.outputs.functionAppSubnetIds[index]
    keyVaultName: keyVault.name
    environment: environment
    runtime: functionApp.runtime
    runtimeVersion: functionApp.runtimeVersion
    tags: tags
  }
  dependsOn: [
    storage
    appInsights
    networking
    keyVault
  ]
}]

// Front Door (CDN/WAF) for public-facing Function Apps
resource frontDoor 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: '${resourcePrefix}-frontdoor'
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// Front Door endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoor
  name: '${resourcePrefix}-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin group for Function Apps
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoor
  name: 'function-apps-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/api/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

// Origins for each Function App
resource origins 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = [for (functionApp, index) in functionApps: {
  parent: originGroup
  name: '${functionApp.name}-origin'
  properties: {
    hostName: functionAppDeployments[index].outputs.functionAppHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: functionAppDeployments[index].outputs.functionAppHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}]

// Route for Function Apps
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: frontDoorEndpoint
  name: 'function-apps-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    origins
  ]
}

// Security policy for WAF
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: frontDoor
  name: 'security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: replace('${resourcePrefix}wafpolicy', '-', '')
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
      maxRequestBodySizeInKb: 128
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Virtual Network ID')
output vnetId string = networking.outputs.vnetId

@description('Storage Account Name')
output storageAccountName string = storage.outputs.storageAccountName

@description('Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey

@description('Function App Names and URLs')
output functionApps array = [for (functionApp, index) in functionApps: {
  name: functionAppDeployments[index].outputs.functionAppName
  url: 'https://${functionAppDeployments[index].outputs.functionAppHostname}'
  principalId: functionAppDeployments[index].outputs.principalId
}]

@description('Front Door Endpoint URL')
output frontDoorUrl string = 'https://${frontDoorEndpoint.properties.hostName}'

@description('Key Vault Name')
output keyVaultName string = keyVault.name
