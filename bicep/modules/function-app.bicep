@description('Function App module with In Control compliance')
param functionAppName string
param location string = resourceGroup().location
param appServicePlanId string
param storageAccountName string
param applicationInsightsKey string
param subnetId string
param keyVaultName string = ''

@description('Environment (dev, test, prod)')
param environment string = 'dev'

@description('Tags for resource tagging')
param tags object = {}

@description('Function App runtime stack')
@allowed(['dotnet', 'node', 'python', 'java'])
param runtime string = 'dotnet'

@description('Runtime version')
param runtimeVersion string = '6'

var functionAppSettings = [
  {
    name: 'AzureWebJobsStorage'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2022-09-01').keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2022-09-01').keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: toLower(functionAppName)
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: applicationInsightsKey
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: runtime
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: runtime == 'node' ? '~18' : ''
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
  // In Control compliance settings
  {
    name: 'WEBSITE_HTTPLOGGING_RETENTION_DAYS'
    value: '30'
  }
  {
    name: 'WEBSITE_LOAD_CERTIFICATES'
    value: '*'
  }
]

// Function App with compliance settings
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  tags: tags
  properties: {
    serverFarmId: appServicePlanId
    siteConfig: {
      appSettings: functionAppSettings
      // In Control compliance - enforce HTTPS and TLS 1.2
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
      // Runtime configuration
      netFrameworkVersion: runtime == 'dotnet' ? 'v${runtimeVersion}.0' : null
      nodeVersion: runtime == 'node' ? '~${runtimeVersion}' : null
      pythonVersion: runtime == 'python' ? runtimeVersion : null
      javaVersion: runtime == 'java' ? runtimeVersion : null
      // Security headers
      ipSecurityRestrictions: []
      scmIpSecurityRestrictions: []
      scmIpSecurityRestrictionsUseMain: false
    }
    httpsOnly: true
    // VNet integration for compliance
    virtualNetworkSubnetId: subnetId
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    clientCertEnabled: false
    hostNamesDisabled: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Configure VNet integration
resource functionAppVnetConnection 'Microsoft.Web/sites/virtualNetworkConnections@2022-09-01' = {
  parent: functionApp
  name: 'vnet-integration'
  properties: {
    vnetResourceId: subnetId
    isSwift: true
  }
}

// Diagnostic settings for compliance monitoring
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${functionAppName}-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: resourceId('Microsoft.OperationalInsights/workspaces', '${functionAppName}-workspace')
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

// Key Vault access policy if Key Vault is provided
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = if (!empty(keyVaultName)) {
  name: '${keyVaultName}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: functionApp.identity.tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

@description('Function App resource ID')
output functionAppId string = functionApp.id

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Function App managed identity principal ID')
output principalId string = functionApp.identity.principalId

@description('Function App managed identity tenant ID')
output tenantId string = functionApp.identity.tenantId
