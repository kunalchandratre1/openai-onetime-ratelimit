# =============================================================================
# 00-prereqs.ps1  -  Verify local tooling + show versions. Non-destructive.
# Run first to confirm your workstation can execute the rest of the pipeline.
# =============================================================================
. "$PSScriptRoot/lib/common.ps1"

Write-Info 'Checking required tooling...'

Assert-Command 'az'
Write-Ok "Azure CLI present: $(az version --query '\"azure-cli\"' -o tsv)"

# Bicep is bundled with az; ensure it is installed/updated.
Invoke-WithRetry -OperationName 'az bicep install' -Action {
    az bicep install 1>$null 2>$null
    az bicep upgrade 1>$null 2>$null
}
Write-Ok "Bicep CLI present: $(az bicep version 2>$null)"

# PowerShell 7+ recommended for cross-platform parity with deploy.sh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warn2 "PowerShell $($PSVersionTable.PSVersion) detected. PowerShell 7+ is recommended."
} else {
    Write-Ok "PowerShell $($PSVersionTable.PSVersion)"
}

# Optional: REST calls in test scripts use curl/Invoke-RestMethod (built-in).
Write-Ok 'Prerequisite check complete.'
Write-Info 'Next: ./01-login-and-select-subscription.ps1 -SubscriptionId <guid>'
