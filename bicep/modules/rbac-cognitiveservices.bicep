// =============================================================================
// modules/rbac-cognitiveservices.bicep  -  Grant a principal the
// "Cognitive Services User" role on a Foundry account (scope = account).
// Ref: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#cognitive-services-user
//      https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy
// Role: Cognitive Services User = a97b65f3-24c7-4388-baec-2e87135dc908
// =============================================================================

param accountName string
param principalId string

@description('Principal type of the identity being granted access.')
param principalType string = 'ServicePrincipal'

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, principalId, cognitiveServicesUserRoleId)
  scope: account
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
  }
}
