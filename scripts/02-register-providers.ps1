# =============================================================================
# 02-register-providers.ps1  -  Register required resource providers (idempotent).
# Ref: https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types
# =============================================================================
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$providers = @(
    'Microsoft.ApiManagement',
    'Microsoft.CognitiveServices',
    'Microsoft.Insights',
    'Microsoft.OperationalInsights',
    'Microsoft.Authorization'
)

foreach ($p in $providers) {
    $state = az provider show -n $p --query registrationState -o tsv 2>$null
    if ($state -eq 'Registered') {
        Write-Ok "$p already registered."
        continue
    }
    Write-Info "Registering $p ..."
    az provider register -n $p 1>$null
}

# Wait for registration to complete (idempotent poll).
foreach ($p in $providers) {
    Invoke-WithRetry -OperationName "wait-$p" -MaxAttempts 20 -InitialDelaySeconds 10 -Action {
        $state = az provider show -n $p --query registrationState -o tsv
        if ($state -ne 'Registered') { throw "$p state=$state" }
        Write-Ok "$p registered."
    }
}
Write-Info 'Next: ./03-validate-quota.ps1 -ParametersFile ../bicep/parameters/dev.parameters.json'
