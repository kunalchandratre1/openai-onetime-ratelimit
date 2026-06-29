// =============================================================================
// apim.bicep  -  API Management instance (Basic v2) + App Insights logger +
//                global (service-scoped) policy.
// Ref: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service
//      https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights
//      https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview
// NOTE: v2 capabilities require API version 2024-05-01 or later.
// =============================================================================

param location string
param tags object
param apimName string

@allowed([
  'Basicv2'
  'Standardv2'
  'Premiumv2'
])
param skuName string

@minValue(1)
@maxValue(10)
param capacity int

param publisherEmail string
param publisherName string

param appInsightsName string
@secure()
param appInsightsInstrumentationKey string

@description('Service-scoped (global) policy XML. Guarded internally to foundry-* APIs.')
param globalPolicyXml string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: capacity
  }
  // System-assigned identity is used by authentication-managed-identity policy
  // to authenticate APIM -> Azure OpenAI data plane (no keys in policy/config).
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Reference existing App Insights to wire up a logger.
resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for Foundry APIs'
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

// Global (All APIs) diagnostic -> App Insights.
resource diagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    metrics: true
    verbosity: 'error'
    httpCorrelationProtocol: 'W3C'
  }
}

// Service-scoped policy. The XML itself guards execution to foundry-* APIs,
// so non-Foundry APIs are unaffected by token quota / burst rules.
resource servicePolicy 'Microsoft.ApiManagement/service/policies@2024-05-01' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: globalPolicyXml
  }
}

output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output identityPrincipalId string = apim.identity.principalId
