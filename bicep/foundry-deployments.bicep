// =============================================================================
// foundry-deployments.bicep  -  Azure AI Foundry / Azure OpenAI accounts and
//                               model deployments across regions.
// Ref: https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts
//      https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/deployments
//      https://learn.microsoft.com/azure/ai-foundry/openai/quotas-limits  (regional, per-subscription, per-model/deployment-type)
//
// IMPORTANT: Deployments under one account must be created serially (the
// CognitiveServices control plane rejects parallel deployment writes). We use
// @batchSize(1) to serialize. Foundry quota is regional/per-subscription/per-model,
// so capacity (TPM units) is supplied as a parameter, never hard-coded.
// =============================================================================

param tags object

@description('Accounts to create: [{ key, name, location }].')
param accounts array

@description('Deployments: [{ accountName, deploymentName, modelName, modelVersion, deploymentType, capacity }].')
param deployments array

// ---- Accounts ----------------------------------------------------------------
module accountModules 'modules/foundry-account.bicep' = [for a in accounts: {
  name: 'foundry-acct-${a.key}'
  params: {
    name: a.name
    location: a.location
    tags: tags
  }
}]

// ---- Deployments (serialized) ------------------------------------------------
// batchSize(1) forces sequential creation to satisfy the control-plane constraint.
@batchSize(1)
module deploymentModules 'modules/foundry-deployment.bicep' = [for (d, i) in deployments: {
  name: 'foundry-dep-${i}'
  params: {
    accountName: d.accountName
    deploymentName: d.deploymentName
    modelName: d.modelName
    modelVersion: d.modelVersion
    deploymentType: d.deploymentType
    capacity: d.capacity
  }
  dependsOn: [
    accountModules
  ]
}]

output accountIds array = [for (a, i) in accounts: accountModules[i].outputs.id]
output accountEndpoints array = [for (a, i) in accounts: {
  name: a.name
  endpoint: accountModules[i].outputs.endpoint
}]
