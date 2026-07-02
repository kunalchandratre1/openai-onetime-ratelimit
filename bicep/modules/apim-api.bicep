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

@description('True => model uses the Azure OpenAI Responses API (e.g. Codex). Adds a POST /responses operation not present in the imported chat-completions spec.')
param isResponses bool = false

@description('Backend base URL for direct routing, e.g. https://acct.openai.azure.com/openai')
param serviceUrl string

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
    // Import the Azure OpenAI inference spec so APIM recognizes this as an LLM API.
    // This enables llm-token-limit token parsing/usage accounting AND ensures the
    // response body is buffered/returned (generic HTTP APIs drop the body).
    apiType: 'http'
    format: 'openapi-link'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json'
    serviceUrl: serviceUrl
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
}

// ---- Responses API operation (Codex etc.) -----------------------------------
// The imported chat-completions inference spec does not define the Responses API
// endpoint. Models whose only supported surface is /responses (e.g. gpt-5.3-codex,
// chatCompletion=false) require this operation to be added explicitly so calls to
// POST {path}/responses route to the backend pool.
resource responsesOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = if (isResponses) {
  parent: api
  name: 'create-response'
  properties: {
    displayName: 'Create Response'
    method: 'POST'
    urlTemplate: '/responses'
    templateParameters: []
    request: {
      queryParameters: [
        {
          name: 'api-version'
          description: 'Azure OpenAI data-plane API version.'
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

output apiName string = api.name
