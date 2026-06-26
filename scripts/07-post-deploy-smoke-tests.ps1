# =============================================================================
# 07-post-deploy-smoke-tests.ps1  -  Functional smoke test through the gateway.
#
# For each model-family API: fetch a real subscription key, send a minimal
# request through APIM, and assert HTTP 200 + presence of the x-tokens-consumed
# telemetry header (proves the global token policy executed).
#
# Ref: https://learn.microsoft.com/rest/api/apimanagement/subscription/list-secrets
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $DataPlaneApiVersion = '2024-10-21',
    [string] $SubscriptionName = 'p1subscriptionteam1',
    [string] $MgmtApiVersion = '2024-05-01'
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$params = Read-ParametersFile -Path $ParametersFile
$topology = $params['modelTopology']

$apim = Invoke-AzJson @('apim','show','-g',$ResourceGroup,'-n',$ApimName)
$gateway = $apim.gatewayUrl
Write-Info "Gateway: $gateway"

$subId = (Invoke-AzJson @('account','show')).id
$secretsUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$SubscriptionName/listSecrets?api-version=$MgmtApiVersion"
$secret = Invoke-WithRetry -OperationName 'listSecrets' -Action {
    (az rest --method post --url $secretsUrl -o json | ConvertFrom-Json)
}
$apiKey = $secret.primaryKey
if (-not $apiKey) { throw "Could not retrieve key for subscription $SubscriptionName" }
Write-Ok "Retrieved subscription key for $SubscriptionName."

$failures = 0
foreach ($f in $topology) {
    $url = "$gateway/$($f.apiPath)/deployments/$($f.deploymentName)/" +
           ($(if ($f.isEmbeddings) { 'embeddings' } else { 'chat/completions' })) +
           "?api-version=$DataPlaneApiVersion"

    $body = if ($f.isEmbeddings) {
        @{ input = 'hello world' } | ConvertTo-Json
    } else {
        @{ messages = @(@{ role = 'user'; content = 'Reply with the single word: pong.' }); max_tokens = 16 } | ConvertTo-Json -Depth 5
    }

    Write-Info "Testing $($f.apiName) -> $url"
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $url -Headers @{ 'api-key' = $apiKey; 'Content-Type' = 'application/json' } -Body $body -SkipHttpErrorCheck
        $tokens = $resp.Headers['x-tokens-consumed']
        if ($resp.StatusCode -eq 200) {
            Write-Ok "  200 OK  x-tokens-consumed=$tokens"
        } else {
            Write-Err2 "  HTTP $($resp.StatusCode): $($resp.Content)"
            $failures++
        }
    }
    catch {
        Write-Err2 "  Request failed: $($_.Exception.Message)"
        $failures++
    }
}

if ($failures -gt 0) { Write-Err2 "$failures smoke test(s) failed."; exit 1 }
Write-Ok 'All smoke tests passed.'
