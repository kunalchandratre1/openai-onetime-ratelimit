// =============================================================================
// appinsights.bicep  -  Workspace-based Application Insights + Log Analytics
// Ref: https://learn.microsoft.com/azure/templates/microsoft.insights/components
//      https://learn.microsoft.com/azure/templates/microsoft.operationalinsights/workspaces
// =============================================================================

param location string
param tags object
param appInsightsName string
param logAnalyticsName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Workspace-based App Insights is required (classic is retired).
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
@secure()
output instrumentationKey string = appInsights.properties.InstrumentationKey
output workspaceId string = workspace.id
