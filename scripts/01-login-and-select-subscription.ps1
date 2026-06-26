# =============================================================================
# 01-login-and-select-subscription.ps1  -  Interactive login + subscription set.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [string] $TenantId
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

# Login only if not already authenticated.
$account = az account show -o json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Info 'Not logged in. Launching az login...'
    if ($TenantId) { az login --tenant $TenantId 1>$null } else { az login 1>$null }
}

Write-Info "Selecting subscription $SubscriptionId..."
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to select subscription $SubscriptionId" }

$current = Invoke-AzJson @('account','show')
Write-Ok "Active subscription: $($current.name) ($($current.id))"
Write-Ok "Tenant: $($current.tenantId)"
Write-Info 'Next: ./02-register-providers.ps1'
