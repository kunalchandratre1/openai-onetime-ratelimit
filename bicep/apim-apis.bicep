// =============================================================================
// apim-apis.bicep  -  One APIM API per model family (NOT per team/subscription).
// Delegates to modules/apim-api.bicep for each family.
// Ref: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
// =============================================================================

param apimName string

@description('[{ name, displayName, path, isEmbeddings, policyXml }]')
param apis array

module apiModules 'modules/apim-api.bicep' = [for a in apis: {
  name: 'api-${a.name}'
  params: {
    apimName: apimName
    apiName: a.name
    displayName: a.displayName
    path: a.path
    isEmbeddings: a.isEmbeddings
    isResponses: a.?isResponses ?? false
    serviceUrl: a.serviceUrl
    policyXml: a.policyXml
  }
}]

output apiNames array = [for a in apis: a.name]
