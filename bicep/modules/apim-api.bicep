// =============================================================================
// modules/apim-api.bicep  -  Single APIM API for one Foundry model family.
// Creates: API + operation(s) + API-scoped policy (routing to backend pool).
//
// Ref: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
//      https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis/operations
//      https://learn.microsoft.com/azure/api-management/set-backend-service-policy
//      https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy
//
// Design notes:
//   - The data-plane shape mirrors Azure OpenAI: POST /deployments/{deployment-id}/...
//   - Routing to the regional pool is done in the API policy via
//     <set-backend-service backend-id="<pool>" />  (backend-id based routing).
//   - APIM appends the operation path to the selected pool member's base url
//     (https://<acct>.openai.azure.com/openai), producing the correct data-plane URL.
//   - api-version is a required query parameter on Azure OpenAI calls.
// =============================================================================

param apimName string
param apiName string
param displayName string

@description('APIM API URL suffix, e.g. gpt5-nano. Combined with deployment path at call time.')
param path string

@description('True => embeddings operation; otherwise chat completions.')
param isEmbeddings bool

@description('API-scoped policy XML (routing + managed-identity auth).')
param policyXml string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    displayName: displayName
    path: path
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    // Subscription key is sent in the standard Azure OpenAI header for drop-in compat.
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'subscription-key'
    }
    // serviceUrl intentionally omitted: the API policy selects the backend pool,
    // and the pool member base-url provides the effective backend host.
    apiType: 'http'
  }
}

// ---- Operation --------------------------------------------------------------
var opName = isEmbeddings ? 'embeddings' : 'chat-completions'
var opDisplay = isEmbeddings ? 'Create embeddings' : 'Create chat completion'
var opUrlTemplate = isEmbeddings ? '/deployments/{deployment-id}/embeddings' : '/deployments/{deployment-id}/chat/completions'

resource operation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: opName
  properties: {
    displayName: opDisplay
    method: 'POST'
    urlTemplate: opUrlTemplate
    templateParameters: [
      {
        name: 'deployment-id'
        description: 'Foundry deployment name (model family deployment id).'
        type: 'string'
        required: true
      }
    ]
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'Azure OpenAI data-plane API version, e.g. 2024-10-21.'
          type: 'string'
          required: true
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'OK'
      }
    ]
  }
}

// ---- API-scoped policy ------------------------------------------------------
// Loaded XML already references the correct backend pool via set-backend-service.
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policyXml
  }
  dependsOn: [
    operation
  ]
}

output apiName string = api.name
