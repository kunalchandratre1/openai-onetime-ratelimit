# =============================================================================
# tests/smoke-tests.ps1  -  Wrapper that runs the functional smoke test suite.
# Delegates to scripts/07-post-deploy-smoke-tests.ps1 (single source of truth).
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $SubscriptionName = 'p1subscriptionteam1'
)
& (Join-Path $PSScriptRoot '../scripts/07-post-deploy-smoke-tests.ps1') `
    -ResourceGroup $ResourceGroup `
    -ApimName $ApimName `
    -ParametersFile $ParametersFile `
    -SubscriptionName $SubscriptionName
