// =============================================================================
// apim-subscriptions.bicep  -  Subscriptions = per-key quota isolation boundary.
// Naming convention: p{i}subscriptionteam{j}.
// Scope = the product, so the key inherits the product's API entitlements.
//
// Ref: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/subscriptions
//      https://learn.microsoft.com/azure/api-management/api-management-subscriptions
//
// The lifetime token cap (2.05M) and 25K TPM burst guardrail are enforced per
// subscription key by the GLOBAL foundry policy keyed on context.Subscription.Id,
// NOT here. This file only provisions the keys.
// =============================================================================

param apimName string

@minValue(1)
@maxValue(200)
param productCount int

@minValue(1)
@maxValue(50)
param subscriptionsPerProduct int

@description('Subscription state. active => key usable immediately.')
@allowed([
  'active'
  'suspended'
])
param subscriptionState string = 'active'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

var productIds = [for i in range(1, productCount): 'p${i}']

// Flatten to one row per (product, team): { name, productId }
// map+flatten lambdas avoid unsupported nested for-expressions (BCP138).
var subscriptionRows = flatten(map(productIds, pid => map(range(1, subscriptionsPerProduct), j => {
  name: '${pid}subscriptionteam${j}'
  productId: pid
})))

resource subscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = [for row in subscriptionRows: {
  parent: apim
  name: row.name
  properties: {
    displayName: row.name
    // Scope to the product so the key can call every API linked to that product.
    scope: '${apim.id}/products/${row.productId}'
    state: subscriptionState
    // allowTracing left default (false) for production hygiene.
  }
}]

output subscriptionNames array = [for row in subscriptionRows: row.name]
output totalSubscriptions int = length(subscriptionRows)
