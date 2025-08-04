@description('Application Insights module with In Control compliance')
param appInsightsName string
param location string = resourceGroup().location

@description('Environment (dev, test, prod)')
param environment string = 'dev'

@description('Tags for resource tagging')
param tags object = {}

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

@description('Application type')
@allowed(['web', 'other'])
param applicationType string = 'web'

@description('Data retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// Log Analytics Workspace (required for Application Insights)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights with In Control compliance
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: applicationType
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    RetentionInDays: retentionInDays
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// Data collection rules for enhanced monitoring
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${appInsightsName}-dcr'
  location: location
  tags: tags
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounterDataSource60'
          samplingFrequencyInSeconds: 60
          streams: [
            'Microsoft-Perf'
          ]
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\Process(w3wp)\\% Processor Time'
            '\\Process(w3wp)\\Private Bytes'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'eventLogsDataSource'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'la-workspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Event'
        ]
        destinations: [
          'la-workspace'
        ]
      }
    ]
  }
}

// Alert rules for monitoring
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appInsightsName}-availability-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when availability drops below 95%'
    severity: 2
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AvailabilityResult'
          metricName: 'availabilityResults/availabilityPercentage'
          operator: 'LessThan'
          threshold: 95
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${appInsightsName}-response-time-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when average response time exceeds 2 seconds'
    severity: 3
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'requests/duration'
          operator: 'GreaterThan'
          threshold: 2000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

@description('Application Insights resource ID')
output appInsightsId string = appInsights.id

@description('Application Insights name')
output appInsightsName string = appInsights.name

@description('Application Insights instrumentation key')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output connectionString string = appInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output workspaceName string = logAnalyticsWorkspace.name
