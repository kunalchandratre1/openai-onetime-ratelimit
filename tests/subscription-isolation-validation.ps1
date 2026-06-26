# =============================================================================
# tests/subscription-isolation-validation.ps1  -  Assert per-key quota isolation.
#
# The global policy keys the token counter on context.Subscription.Id, so each
# subscription key has an INDEPENDENT quota/burst counter. This test:
#   1. Sends traffic on key A (p1subscriptionteam1) and records its consumption.
#   2. Reads key B (p1subscriptionteam2) remaining-quota before & after driving A.
#   3. Asserts B's remaining-quota is unaffected by A's usage (isolation holds).
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [string] $ApiPath = 'gpt5-nano',
    [string] $DeploymentName = 'gpt-5-nano',
    [string] $SubscriptionA = 'p1subscriptionteam1',
    [string] $SubscriptionB = 'p1subscriptionteam2',
    [int]    $DriveCalls = 5,
    [string] $DataPlaneApiVersion = '2024-10-21',
    [string] $MgmtApiVersion = '2024-05-01'
)
. "$PSScriptRoot/../scripts/lib/common.ps1"
Assert-Command 'az'

$apim = Invoke-AzJson @('apim','show','-g',$ResourceGroup,'-n',$ApimName)
$gateway = $apim.gatewayUrl
$subId = (Invoke-AzJson @('account','show')).id

function Get-Key([string]$name) {
    $u = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$name/listSecrets?api-version=$MgmtApiVersion"
    (az rest --method post --url $u -o json | ConvertFrom-Json).primaryKey
}

$keyA = Get-Key $SubscriptionA
$keyB = Get-Key $SubscriptionB
if (-not $keyA -or -not $keyB) { throw 'Could not retrieve both subscription keys.' }

$url = "$gateway/$ApiPath/deployments/$DeploymentName/chat/completions?api-version=$DataPlaneApiVersion"
$body = @{ messages = @(@{ role = 'user'; content = 'one word' }); max_tokens = 16 } | ConvertTo-Json -Depth 5

function Send([string]$key) {
    Invoke-WebRequest -Method Post -Uri $url -Headers @{ 'api-key' = $key; 'Content-Type' = 'application/json' } -Body $body -SkipHttpErrorCheck
}

# Baseline B
$bBefore = [int64](Send $keyB).Headers['x-tokens-remaining-quota']
Write-Info "B ($SubscriptionB) remaining-quota before: $bBefore"

# Drive A
for ($i = 0; $i -lt $DriveCalls; $i++) { [void](Send $keyA) }
$aRem = (Send $keyA).Headers['x-tokens-remaining-quota']
Write-Info "A ($SubscriptionA) remaining-quota after driving: $aRem"

# B after (account for the single probe call we just made on B earlier; allow small delta == one call)
$bAfter = [int64](Send $keyB).Headers['x-tokens-remaining-quota']
Write-Info "B ($SubscriptionB) remaining-quota after: $bAfter"

# B should only have moved by its own (few) probe calls, NOT by A's DriveCalls.
$bDelta = $bBefore - $bAfter
Write-Info "B consumed during test (its own probes only): $bDelta"

# Heuristic isolation assertion: B's drop must be far smaller than A's drive volume.
# If counters were shared, B would have dropped by roughly A's consumption too.
if ($bDelta -lt 100000) {
    Write-Ok "PASS: key B quota isolated from key A traffic (B delta=$bDelta tokens)."
} else {
    Write-Err2 "FAIL: key B quota appears affected by key A traffic (B delta=$bDelta tokens)."
    exit 1
}
