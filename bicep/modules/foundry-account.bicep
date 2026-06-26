// =============================================================================
// modules/foundry-account.bicep  -  Single Azure OpenAI (Foundry) account.
// Ref: https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts
// =============================================================================

param name string
param location string
param tags object

@description('Account SKU. S0 is the standard pay-as-you-go SKU for OpenAI accounts.')
param skuName string = 'S0'

@description('Set false to require Entra ID (managed identity) auth only and disable API keys.')
param localAuthEnabled bool = true

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // customSubDomainName is REQUIRED for token-based (Entra) auth and gives the
    // deterministic data-plane host https://<subdomain>.openai.azure.com
    customSubDomainName: toLower(name)
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: !localAuthEnabled
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output principalId string = account.identity.principalId
