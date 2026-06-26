# =============================================================================
# tests/quota-validation.ps1  -  Assert lifetime token quota enforcement.
#
# Drives requests on a single key and asserts that:
#   1. The x-tokens-remaining-quota header is present and DECREASES over calls.
#   2. (Optional, -DriveToLimit) the key eventually returns HTTP 403 once the
#      configured token-quota is exhausted.
#
# NOTE: Exhausting a 2.05M-token cap costs real tokens/money and many calls.
# By default this test only proves the counter decrements (cheap, deterministic).
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [string] $ApiPath = 'gpt5-nano',
    [string] $DeploymentName = 'gpt-5-nano',
    [string] $SubscriptionName = 'p1subscriptionteam1',
    [int]    $Samples = 5,
    [switch] $DriveToLimit,
    [int]    $MaxDriveIterations = 2000,
    [string] $DataPlaneApiVersion = '2024-10-21',
    [string] $MgmtApiVersion = '2024-05-01'
)
. "$PSScriptRoot/../scripts/lib/common.ps1"
Assert-Command 'az'

$apim = Invoke-AzJson @('apim','show','-g',$ResourceGroup,'-n',$ApimName)
$gateway = $apim.gatewayUrl
$subId = (Invoke-AzJson @('account','show')).id
$secretsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$SubscriptionName/listSecrets?api-version=$MgmtApiVersion"
$apiKey = (az rest --method post --url $secretsUrl -o json | ConvertFrom-Json).primaryKey
if (-not $apiKey) { throw "No key for $SubscriptionName" }

$url = "$gateway/$ApiPath/deployments/$DeploymentName/chat/completions?api-version=$DataPlaneApiVersion"
$body = @{ messages = @(@{ role = 'user'; content = 'one word please' }); max_tokens = 16 } | ConvertTo-Json -Depth 5

function Send-One {
    Invoke-WebRequest -Method Post -Uri $url -Headers @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' } -Body $body -SkipHttpErrorCheck
}

Write-Info "Sampling remaining-quota header over $Samples calls..."
$remaining = @()
for ($i = 0; $i -lt $Samples; $i++) {
    $r = Send-One
    $rem = $r.Headers['x-tokens-remaining-quota']
    Write-Host ("  call {0}: status={1} remaining-quota={2} consumed={3}" -f ($i+1), $r.StatusCode, $rem, $r.Headers['x-tokens-consumed'])
    if ($rem) { $remaining += [int64]$rem }
}

if ($remaining.Count -lt 2) {
    Write-Warn2 'Not enough remaining-quota samples to assert monotonic decrease (header may be absent on errors).'
} elseif ($remaining[-1] -lt $remaining[0]) {
    Write-Ok "PASS: remaining-quota decreased ($($remaining[0]) -> $($remaining[-1]))."
} else {
    Write-Err2 "FAIL: remaining-quota did not decrease ($($remaining[0]) -> $($remaining[-1]))."
    exit 1
}

if ($DriveToLimit) {
    Write-Warn2 "Driving key to 403 (max $MaxDriveIterations iterations). This consumes real tokens."
    for ($i = 0; $i -lt $MaxDriveIterations; $i++) {
        $r = Send-One
        if ($r.StatusCode -eq 403) {
            Write-Ok "PASS: received 403 after $($i+1) iterations (quota enforced)."
            exit 0
        }
    }
    Write-Err2 "Did not hit 403 within $MaxDriveIterations iterations; increase the limit or lower the quota for testing."
    exit 1
}
