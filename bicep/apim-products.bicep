// =============================================================================
// apim-products.bicep  -  Products = entitlement boundary. p1..pN.
// Each product is published, requires subscription + (no) approval, and is
// linked to EVERY model-family API ("p1..pN: all models" per design).
//
// Ref: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/products
//      https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/products/apis
//      https://learn.microsoft.com/azure/api-management/api-management-howto-add-products
// =============================================================================

param apimName string

@minValue(1)
@maxValue(200)
param productCount int

@description('All model-family API names to attach to every product.')
param apiNames array

@description('Require admin approval before a subscription is active.')
param approvalRequired bool = false

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// 1-based product ids: p1 .. pN
var productIds = [for i in range(1, productCount): 'p${i}']

// Cartesian product of (product x api) for the link resources.
// map+flatten lambdas avoid unsupported nested for-expressions (BCP138).
var productApiPairs = flatten(map(productIds, pid => map(apiNames, apiName => {
  product: pid
  api: apiName
})))

resource products 'Microsoft.ApiManagement/service/products@2024-05-01' = [for pid in productIds: {
  parent: apim
  name: pid
  properties: {
    displayName: pid
    description: 'Foundry entitlement product ${pid} (all model families).'
    subscriptionRequired: true
    approvalRequired: approvalRequired
    // subscriptionsLimit is intentionally NOT set here: per-subscription isolation
    // and lifetime quota are enforced by policy (llm-token-limit), not by product
    // subscription caps. Set a value if you also want a hard count cap per product.
    state: 'published'
  }
}]

// Link every API to every product. Child name = the API name.
resource productApiLinks 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for pair in productApiPairs: {
  name: '${apimName}/${pair.product}/${pair.api}'
  dependsOn: [
    products
  ]
}]

output productIds array = productIds
