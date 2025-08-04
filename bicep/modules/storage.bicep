@description('Storage Account module with In Control compliance')
param storageAccountName string
param location string = resourceGroup().location

@description('Environment (dev, test, prod)')
param environment string = 'dev'

@description('Tags for resource tagging')
param tags object = {}

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

@description('Enable hierarchical namespace for Data Lake')
param enableHierarchicalNamespace bool = false

// Storage Account with In Control compliance
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    // In Control compliance settings
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    isHnsEnabled: enableHierarchicalNamespace
    
    // Network access rules
    networkAcls: {
      defaultAction: 'Allow' // Will be restricted via private endpoints in production
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    
    // Encryption settings
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
        table: {
          keyType: 'Account'
          enabled: true
        }
        queue: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
    }
    
    // Access tier
    accessTier: 'Hot'
  }
}

// Blob service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    // In Control compliance - disable anonymous access
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    versioning: {
      enabled: true
    }
    isVersioningEnabled: true
  }
}

// File service configuration
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    protocolSettings: {
      smb: {
        versions: 'SMB3.0;SMB3.1.1'
        authenticationMethods: 'Kerberos;NTLMv2'
        kerberosTicketEncryption: 'AES-256'
        channelEncryption: 'AES-128-CCM;AES-128-GCM;AES-256-GCM'
      }
    }
  }
}

// Queue service configuration
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Table service configuration
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Function App content share
resource functionContentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  parent: fileService
  name: 'function-content'
  properties: {
    shareQuota: 5120
    enabledProtocols: 'SMB'
    accessTier: 'Hot'
  }
}

// Diagnostic settings for compliance monitoring
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${storageAccountName}-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: resourceId('Microsoft.OperationalInsights/workspaces', '${storageAccountName}-workspace')
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account primary endpoints')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints

@description('Storage Account connection string')
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
