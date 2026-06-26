# =============================================================================
# 08-load-test.ps1  -  Lightweight load / quota-drive test against one key.
#
# Sends N small requests through a single subscription key on one model API and
# tracks the x-tokens-consumed / x-tokens-remaining-quota headers to observe
# burst (429) and quota (403) enforcement. NOT a substitute for a real load tool
# (e.g. Azure Load Testing) but useful for behavioural validation.
#
# This is a deliberately modest generator. To actually exhaust a 2.05M cap you
# would need a large request volume; use -Iterations accordingly and expect cost.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $ApiPath = 'gpt5-nano',
    [string] $DeploymentName = 'gpt-5-nano',
    [string] $SubscriptionName = 'p1subscriptionteam1',
    [int]    $Iterations = 50,
    [int]    $Concurrency = 5,
    [string] $DataPlaneApiVersion = '2024-10-21',
    [string] $MgmtApiVersion = '2024-05-01'
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$apim = Invoke-AzJson @('apim','show','-g',$ResourceGroup,'-n',$ApimName)
$gateway = $apim.gatewayUrl
$subId = (Invoke-AzJson @('account','show')).id
$secretsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$SubscriptionName/listSecrets?api-version=$MgmtApiVersion"
$apiKey = (az rest --method post --url $secretsUrl -o json | ConvertFrom-Json).primaryKey
if (-not $apiKey) { throw "Could not retrieve key for $SubscriptionName" }

$url = "$gateway/$ApiPath/deployments/$DeploymentName/chat/completions?api-version=$DataPlaneApiVersion"
$body = @{ messages = @(@{ role = 'user'; content = 'Reply with one word.' }); max_tokens = 16 } | ConvertTo-Json -Depth 5

Write-Info "Driving $Iterations requests (concurrency $Concurrency) at $url"

$results = 1..$Iterations | ForEach-Object -ThrottleLimit $Concurrency -Parallel {
    $u = $using:url; $k = $using:apiKey; $b = $using:body
    try {
        $r = Invoke-WebRequest -Method Post -Uri $u -Headers @{ 'api-key' = $k; 'Content-Type' = 'application/json' } -Body $b -SkipHttpErrorCheck
        [pscustomobject]@{
            Status    = [int]$r.StatusCode
            Consumed  = $r.Headers['x-tokens-consumed']
            Remaining = $r.Headers['x-tokens-remaining-quota']
        }
    } catch {
        [pscustomobject]@{ Status = -1; Consumed = $null; Remaining = $null }
    }
}

$ok   = ($results | Where-Object Status -eq 200).Count
$r429 = ($results | Where-Object Status -eq 429).Count
$r403 = ($results | Where-Object Status -eq 403).Count
$err  = ($results | Where-Object { $_.Status -notin 200,429,403 }).Count
$last = $results | Where-Object Status -eq 200 | Select-Object -Last 1

Write-Host ''
Write-Ok  "200 OK            : $ok"
Write-Warn2 "429 (burst/TPM)   : $r429"
Write-Warn2 "403 (quota)       : $r403"
Write-Err2  "other/errors      : $err"
if ($last) { Write-Info "Last remaining-quota header: $($last.Remaining)" }
Write-Info 'Interpretation: 429s prove burst guardrail; 403s prove lifetime token quota enforcement.'
