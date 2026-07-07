// =============================================================================
// modules/apim-product-batch.bicep  -  One product + its API links + its keys.
//
// Why this exists:
//   ARM enforces hard limits of 800 resources per deployment and 800 iterations
//   per copy loop. Creating all (productCount x subscriptionsPerProduct) keys in
//   a single flat loop breaks past ~800 keys (e.g. prod = 110 x 10 = 1100).
//   Batching ONE product per nested deployment keeps every inner loop small
//   (<= subscriptionsPerProduct) and the OUTER loop equal to productCount, so the
//   design scales to hundreds of products x tens of keys without hitting limits,
//   while still working for small counts (e.g. dev = 10 x 5 = 50).
//
// Ref: https://aka.ms/arm-resource-loops   (copy limits)
//      https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/products
//      https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/products/apis
//      https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/subscriptions
// =============================================================================

param apimName string

@description('1-based product index. Product id = p{productIndex}.')
@minValue(1)
param productIndex int

@description('All model-family API names to attach to this product.')
param apiNames array

@description('Number of subscription keys to create for this product.')
@minValue(1)
@maxValue(50)
param subscriptionsPerProduct int

@description('Require admin approval before a subscription is active.')
param approvalRequired bool = false

@description('Subscription state. active => key usable immediately.')
@allowed([
  'active'
  'suspended'
])
param subscriptionState string = 'active'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

var productId = 'p${productIndex}'

// Team key names for this product: p{i}subscriptionteam{j}
var subscriptionNames = [for j in range(1, subscriptionsPerProduct): '${productId}subscriptionteam${j}']

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: productId
  properties: {
    displayName: productId
    description: 'Foundry entitlement product ${productId} (all model families).'
    subscriptionRequired: true
    approvalRequired: approvalRequired
    // Per-subscription isolation + lifetime quota are enforced by policy
    // (llm-token-limit), not by product subscription caps.
    state: 'published'
  }
}

// Link every API to this product. Child name = the API name.
resource productApiLinks 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for apiName in apiNames: {
  name: '${apimName}/${productId}/${apiName}'
  dependsOn: [
    product
  ]
}]

// Per-key quota isolation boundary, scoped to this product.
resource subscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for name in subscriptionNames: {
  parent: apim
  name: name
  properties: {
    displayName: name
    // Scope to the product so the key can call every API linked to that product.
    scope: '${apim.id}/products/${productId}'
    state: subscriptionState
  }
  dependsOn: [
    product
  ]
}]

output productId string = productId
output subscriptionNames array = subscriptionNames
