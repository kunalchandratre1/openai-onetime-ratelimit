// =============================================================================
// main.bicep  -  Orchestrator (resource group scoped)
// -----------------------------------------------------------------------------
// Builds an Azure API Management (Basic v2) "front door" for Azure AI Foundry /
// Azure OpenAI model access with:
//   - Multi-region Foundry (Cognitive Services / OpenAI) accounts + deployments
//   - One APIM API per model family (NOT one per team/subscription)
//   - Backend entities per regional model endpoint + priority backend POOLS
//   - Circuit-breaker based failover on each backend
//   - Products (entitlement boundary) + per-product subscriptions (quota boundary)
//   - Global token-quota + burst policy scoped only to foundry-* APIs
//
// Source-of-truth references (Microsoft Learn):
//   - APIM v2 tiers overview:            https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview
//   - APIM backends / pools / breaker:   https://learn.microsoft.com/azure/api-management/backends
//   - llm-token-limit policy:            https://learn.microsoft.com/azure/api-management/llm-token-limit-policy
//   - quota-by-key policy:               https://learn.microsoft.com/azure/api-management/quota-by-key-policy
//   - Foundry/OpenAI quotas (regional):  https://learn.microsoft.com/azure/ai-foundry/openai/quotas-limits
//   - CognitiveServices accounts schema: https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts
//   - APIM service schema:               https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service
//
// NOTE: This template is intended for MANUAL review and execution by the operator.
//       It is parameterised; defaults live in /bicep/parameters/*.json.
// =============================================================================

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Core / naming
// -----------------------------------------------------------------------------
@description('Location for control-plane resources (APIM, App Insights, Log Analytics). Foundry accounts use their own per-region location.')
param location string = resourceGroup().location

@description('Short, lowercase workload prefix used in resource names. e.g. "apimfoundry".')
@minLength(3)
@maxLength(20)
param namePrefix string

@description('Environment tag/suffix, e.g. dev | test | prod.')
param environment string = 'dev'

@description('Common resource tags.')
param tags object = {
  workload: 'apim-foundry-frontdoor'
  environment: environment
  managedBy: 'bicep'
}

// -----------------------------------------------------------------------------
// APIM
// -----------------------------------------------------------------------------
@description('APIM instance name (must be globally unique).')
param apimName string = '${namePrefix}-apim-${environment}'

@description('APIM SKU. Basic v2 per design baseline.')
@allowed([
  'Basicv2'
  'Standardv2'
  'Premiumv2'
])
param apimSkuName string = 'Basicv2'

@description('APIM scale units (Basic v2 supports up to 10).')
@minValue(1)
@maxValue(10)
param apimCapacity int = 1

@description('Publisher email shown on the developer portal / notifications.')
param apimPublisherEmail string

@description('Publisher organisation name.')
param apimPublisherName string

// -----------------------------------------------------------------------------
// Observability
// -----------------------------------------------------------------------------
@description('Application Insights component name.')
param appInsightsName string = '${namePrefix}-appi-${environment}'

@description('Log Analytics workspace name (backing store for App Insights workspace-based mode).')
param logAnalyticsName string = '${namePrefix}-log-${environment}'

// -----------------------------------------------------------------------------
// Foundry topology
// -----------------------------------------------------------------------------
@description('''
Foundry (Azure OpenAI) accounts keyed by short region key.
Each value: { name: <globally-unique account name>, location: <azure region> }.
The data-plane host is derived deterministically as https://<name>.openai.azure.com/openai
(customSubDomainName is set to toLower(name)).
Example key: swc | eus2 | wus3
''')
param foundryAccounts object

@description('''
Model family topology. One entry per model family => one APIM API + one backend pool.
Each entry:
{
  key:            'gpt5-nano'                 // short key, used in backend names
  apiName:        'foundry-gpt5-nano-api'     // APIM API name (MUST start with foundry-)
  apiDisplayName: 'Foundry GPT-5 Nano'
  apiPath:        'gpt5-nano'                  // APIM API URL suffix
  poolName:       'pool-foundry-gpt5-nano'    // backend pool name
  deploymentName: 'gpt-5-nano'                // Foundry deployment id (used in data-plane path)
  modelName:      'gpt-5-nano'                // Foundry model name
  modelVersion:   '2025-08-07'               // Foundry model version  (OPERATOR MUST CONFIRM)
  deploymentType: 'GlobalStandard'           // SKU name on the deployment
  isEmbeddings:   false
  regions: [ { account: 'swc', priority: 1 }, { account: 'eus2', priority: 1 }, { account: 'wus3', priority: 2 } ]
}
''')
param modelTopology array

@description('''
Per (region,model) deployment capacity in TPM units (each unit = 1,000 TPM for Standard-family SKUs).
Keyed "<regionKey>_<modelKey>", e.g. "swc_gpt5-nano": 50.
Treated as PARAMETERISED INPUT, never hard-coded business logic.
''')
param capacities object

// -----------------------------------------------------------------------------
// Products & subscriptions (entitlement + quota boundaries)
// -----------------------------------------------------------------------------
@description('Number of APIM products to create (p1..pN). Current setting = 10.')
@minValue(1)
@maxValue(200)
param productCount int = 10

@description('Number of subscriptions per product. Current setting = 5. (Naming: p{i}subscriptionteam{j}).')
@minValue(1)
@maxValue(50)
param subscriptionsPerProduct int = 5

@description('Lifetime token cap per subscription key. See known-limitations.md re: true-lifetime gap (enforced via Yearly token-quota).')
param subscriptionTokenQuota int = 2050000

@description('Token-quota reset period for llm-token-limit. Closest supported approximation to "lifetime". One of Hourly|Daily|Weekly|Monthly|Yearly.')
@allowed([
  'Hourly'
  'Daily'
  'Weekly'
  'Monthly'
  'Yearly'
])
param subscriptionTokenQuotaPeriod string = 'Yearly'

@description('Burst guardrail tokens-per-minute per subscription key.')
param subscriptionTpmGuardrail int = 25000

// =============================================================================
// Derived collections (computed, not hard-coded)
// =============================================================================

// Flat list of Foundry accounts to create: [{ key, name, location }]
var foundryAccountList = [for a in items(foundryAccounts): {
  key: a.key
  name: a.value.name
  location: a.value.location
}]

// Flat list of model deployments: one per (family, region).
// Nested map+flatten lambdas avoid unsupported nested for-expressions (BCP138).
var deploymentMatrix = flatten(map(modelTopology, f => map(f.regions, r => {
  accountName: foundryAccounts[r.account].name
  deploymentName: f.deploymentName
  modelName: f.modelName
  modelVersion: f.modelVersion
  deploymentType: f.deploymentType
  capacity: capacities['${r.account}_${f.key}']
})))

// Flat list of backend entities: one per (family, region).
// Data-plane host derived deterministically from account name.
var backendList = flatten(map(modelTopology, f => map(f.regions, r => {
  name: 'be-${f.key}-${r.account}'
  url: 'https://${toLower(foundryAccounts[r.account].name)}.openai.azure.com/openai'
})))

// Backend pools: one per family, members carry priority for failover.
var poolList = [for f in modelTopology: {
  name: f.poolName
  members: map(f.regions, r => {
    name: 'be-${f.key}-${r.account}'
    priority: r.priority
    weight: 1
  })
}]

// Per-API policy XML, loaded at compile time and mapped by API name.
// (loadTextContent requires literal paths -> explicit map.)
var apiPolicyMap = {
  'foundry-gpt5-nano-api': loadTextContent('../policies/api-foundry-gpt5-nano-policy.xml')
  'foundry-gpt5-mini-api': loadTextContent('../policies/api-foundry-gpt5-mini-policy.xml')
  'foundry-gpt52-api': loadTextContent('../policies/api-foundry-gpt52-policy.xml')
  'foundry-gpt54-api': loadTextContent('../policies/api-foundry-gpt54-policy.xml')
  'foundry-codex-api': loadTextContent('../policies/api-foundry-codex-policy.xml')
  'foundry-embeddings-api': loadTextContent('../policies/api-foundry-embeddings-policy.xml')
}

// API descriptors consumed by apim-apis module.
// Token-quota placeholders in each API policy are substituted at deploy time so the
// per-key governance values stay parameterised (header-emitting llm-token-limit must
// live at API scope, not global scope).
var apiList = [for f in modelTopology: {
  name: f.apiName
  displayName: f.apiDisplayName
  path: f.apiPath
  poolName: f.poolName
  isEmbeddings: f.isEmbeddings
  isResponses: f.?isResponses ?? false
  serviceUrl: 'https://${toLower(foundryAccounts[f.regions[0].account].name)}.openai.azure.com/openai'
  policyXml: replace(replace(replace(apiPolicyMap[f.apiName], '{{TOKEN_QUOTA}}', string(subscriptionTokenQuota)), '{{TOKEN_QUOTA_PERIOD}}', subscriptionTokenQuotaPeriod), '{{TPM_GUARDRAIL}}', string(subscriptionTpmGuardrail))
}]

// All API names (used to link every API to every product => "all models" entitlement).
var allApiNames = [for f in modelTopology: f.apiName]

// Global foundry policy (token quota + burst), guarded to foundry-* APIs only.
// Placeholder tokens are replaced at deploy time so values stay parameterised.
var globalPolicyTemplate = loadTextContent('../policies/global-foundry-policy.xml')
var globalPolicyXml = replace(replace(replace(globalPolicyTemplate, '{{TOKEN_QUOTA}}', string(subscriptionTokenQuota)), '{{TOKEN_QUOTA_PERIOD}}', subscriptionTokenQuotaPeriod), '{{TPM_GUARDRAIL}}', string(subscriptionTpmGuardrail))

// =============================================================================
// Modules
// =============================================================================

module observability 'appinsights.bicep' = {
  name: 'observability'
  params: {
    location: location
    tags: tags
    appInsightsName: appInsightsName
    logAnalyticsName: logAnalyticsName
  }
}

module apim 'apim.bicep' = {
  name: 'apim'
  params: {
    location: location
    tags: tags
    apimName: apimName
    skuName: apimSkuName
    capacity: apimCapacity
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    appInsightsName: observability.outputs.appInsightsName
    appInsightsInstrumentationKey: observability.outputs.instrumentationKey
    globalPolicyXml: globalPolicyXml
  }
}

module foundry 'foundry-deployments.bicep' = {
  name: 'foundry'
  params: {
    tags: tags
    accounts: foundryAccountList
    deployments: deploymentMatrix
  }
}

// Grant APIM managed identity "Cognitive Services User" on each Foundry account
// so the authentication-managed-identity policy can mint data-plane tokens.
module rbac 'modules/rbac-cognitiveservices.bicep' = [for (a, i) in foundryAccountList: {
  name: 'rbac-${a.key}'
  params: {
    accountName: a.name
    principalId: apim.outputs.identityPrincipalId
  }
  dependsOn: [
    foundry
  ]
}]

module backends 'apim-backends.bicep' = {
  name: 'apim-backends'
  params: {
    apimName: apim.outputs.apimName
    backends: backendList
    pools: poolList
  }
}

module apis 'apim-apis.bicep' = {
  name: 'apim-apis'
  params: {
    apimName: apim.outputs.apimName
    apis: apiList
  }
  dependsOn: [
    backends
  ]
}

module products 'apim-products.bicep' = {
  name: 'apim-products'
  params: {
    apimName: apim.outputs.apimName
    productCount: productCount
    apiNames: allApiNames
  }
  dependsOn: [
    apis
  ]
}

module subscriptions 'apim-subscriptions.bicep' = {
  name: 'apim-subscriptions'
  params: {
    apimName: apim.outputs.apimName
    productCount: productCount
    subscriptionsPerProduct: subscriptionsPerProduct
  }
  dependsOn: [
    products
  ]
}

// =============================================================================
// Outputs
// =============================================================================
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.apimName
output apimIdentityPrincipalId string = apim.outputs.identityPrincipalId
output foundryAccountNames array = [for a in foundryAccountList: a.name]
output totalSubscriptions int = productCount * subscriptionsPerProduct
output theoreticalTokenCeiling int = productCount * subscriptionsPerProduct * subscriptionTokenQuota
