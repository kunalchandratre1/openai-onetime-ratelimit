// =============================================================================
// apim-backends.bicep  -  Backend entities (one per regional model endpoint) +
//                         priority backend POOLS (one per model family) with
//                         circuit-breaker based failover.
//
// Ref: https://learn.microsoft.com/azure/api-management/backends
//      https://learn.microsoft.com/rest/api/apimanagement/backend/create-or-update
//
// !!! PREVIEW DEPENDENCY (explicitly flagged) !!!
// Backend POOLS (properties.type = 'Pool') and the backend circuitBreaker
// property are surfaced through a PREVIEW API version of
// Microsoft.ApiManagement/service/backends. We pin 2024-06-01-preview.
// The feature itself is documented & supported on Basic v2 (only the Consumption
// tier excludes the circuit breaker). If your tenant requires GA-only API
// versions, see known-limitations.md for the supported fallback (set-backend-service
// with explicit base-url + retry policy).
// =============================================================================

param apimName string

@description('Single backends: [{ name, url }] where url = https://<acct>.openai.azure.com/openai')
param backends array

@description('Pools: [{ name, members: [{ name, priority, weight }] }]')
param pools array

// Circuit-breaker tuning (per official Azure OpenAI guidance: trip on 429 + 5xx,
// honour Retry-After which Azure OpenAI returns on throttling).
@description('Failure count within the interval that trips the breaker.')
param breakerFailureCount int = 3
@description('Failure sampling interval (ISO 8601 duration).')
param breakerInterval string = 'PT1M'
@description('How long the breaker stays open before half-open retry (ISO 8601 duration).')
param breakerTripDuration string = 'PT1M'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ---- Single backends (with circuit breaker) ---------------------------------
resource backendEntities 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for b in backends: {
  parent: apim
  name: b.name
  properties: {
    protocol: 'http'
    url: b.url
    // APIM mints an Entra token for Azure OpenAI using its managed identity and
    // presents it to the backend. Authenticating at the backend (not via an inbound
    // authentication-managed-identity policy) keeps the GenAI request/response
    // pipeline intact so token counting and response bodies work correctly.
    credentials: {
      #disable-next-line BCP037
      managedIdentity: {
        resource: 'https://cognitiveservices.azure.com'
      }
    }
    circuitBreaker: {
      rules: [
        {
          name: 'openai-breaker'
          failureCondition: {
            count: breakerFailureCount
            interval: breakerInterval
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
              {
                min: 500
                max: 599
              }
            ]
          }
          tripDuration: breakerTripDuration
          // Azure OpenAI returns Retry-After on 429; respect it before re-sending.
          acceptRetryAfter: true
        }
      ]
    }
  }
}]

// ---- Pools (priority-based failover) ----------------------------------------
// Members reference single backends by relative id "/backends/<name>".
// API Management routes to lower-priority groups only when all higher-priority
// members are unavailable (their circuit breakers are tripped).
resource backendPools 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for p in pools: {
  parent: apim
  name: p.name
  properties: {
    type: 'Pool'
    pool: {
      services: [for m in p.members: {
        id: '/backends/${m.name}'
        priority: m.priority
        weight: m.weight
      }]
    }
  }
  dependsOn: [
    backendEntities
  ]
}]

output backendNames array = [for b in backends: b.name]
output poolNames array = [for p in pools: p.name]
