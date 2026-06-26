# =============================================================================
# 04-deploy-infra.ps1  -  Create resource group, run what-if, then deploy.
#
# Deploys the FULL stack via main.bicep (idempotent): App Insights, APIM (Basic v2),
# Foundry accounts + model deployments, RBAC, backends/pools, APIs, products,
# subscriptions, and the global foundry policy.
#
# Usage:
#   ./04-deploy-infra.ps1 -ResourceGroup rg-apim-foundry-dev -Location swedencentral `
#       -ParametersFile ../bicep/parameters/dev.parameters.json
#   Add -WhatIfOnly to preview changes without deploying.
# Ref: https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-cli
#      https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $DeploymentName = "apim-foundry-$((Get-Date).ToString('yyyyMMddHHmmss'))",
    [switch] $WhatIfOnly
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$templateFile = Join-Path $PSScriptRoot '../bicep/main.bicep'
if (-not (Test-Path $templateFile)) { throw "Template not found: $templateFile" }
if (-not (Test-Path $ParametersFile)) { throw "Parameters file not found: $ParametersFile" }

# 1) Resource group (idempotent).
Write-Info "Ensuring resource group '$ResourceGroup' in '$Location'..."
az group create -n $ResourceGroup -l $Location 1>$null
Write-Ok "Resource group ready."

# 2) Lint/build the template early to fail fast.
Write-Info 'Building Bicep (lint)...'
az bicep build --file $templateFile 1>$null
Write-Ok 'Bicep build succeeded.'

# 3) What-if (always shown).
Write-Info 'Running what-if (preview of changes)...'
az deployment group what-if `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --template-file $templateFile `
    --parameters $ParametersFile

if ($WhatIfOnly) {
    Write-Warn2 'WhatIfOnly specified - stopping before deployment.'
    return
}

# 4) Deploy (idempotent; retries transient failures).
Write-Info "Deploying '$DeploymentName'..."
Invoke-WithRetry -OperationName 'az deployment group create' -MaxAttempts 3 -InitialDelaySeconds 15 -Action {
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file $templateFile `
        --parameters $ParametersFile `
        --verbose
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed (exit $LASTEXITCODE)" }
}

Write-Ok 'Deployment complete. Outputs:'
$outputs = Invoke-AzJson @('deployment','group','show','-g',$ResourceGroup,'-n',$DeploymentName,'--query','properties.outputs')
$outputs | ConvertTo-Json -Depth 6
Write-Info 'Next: ./05-apply-apim-artifacts.ps1 (only needed when re-applying policies without a full redeploy).'
