// =============================================================================
// modules/foundry-deployment.bicep  -  Single model deployment on an account.
// Ref: https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/deployments
//      https://learn.microsoft.com/azure/ai-foundry/openai/how-to/deployment-types
// =============================================================================

param accountName string
param deploymentName string
param modelName string
param modelVersion string

@description('Deployment SKU name == deployment type, e.g. GlobalStandard | DataZoneStandard | Standard.')
param deploymentType string

@description('Capacity in TPM units (1 unit = 1,000 TPM for Standard-family). Parameterised quota input.')
param capacity int

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: deploymentType
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    // Keep deployments deterministic for reproducible IaC; operator chooses upgrades.
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

output id string = deployment.id
output name string = deployment.name
