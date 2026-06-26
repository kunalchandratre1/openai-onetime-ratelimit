# =============================================================================
# 05-apply-apim-artifacts.ps1  -  (Re)apply policy XML to an existing APIM.
#
# main.bicep already deploys all policies. Use THIS script when you iterate on
# policy XML only and want to push changes WITHOUT a full redeploy. Idempotent
# (PUT is upsert). Substitutes the global policy placeholders from the params file.
#
# Ref: https://learn.microsoft.com/rest/api/apimanagement/policy/create-or-update
#      https://learn.microsoft.com/rest/api/apimanagement/api-policy/create-or-update
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $ApiVersion = '2024-05-01'
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$policiesDir = Join-Path $PSScriptRoot '../policies'
$params = Read-ParametersFile -Path $ParametersFile
$subId = (Invoke-AzJson @('account','show')).id
$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

function Set-Policy {
    param([string]$Url, [string]$Xml, [string]$Label)
    $body = @{ properties = @{ format = 'rawxml'; value = $Xml } } | ConvertTo-Json -Depth 5
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $body -Encoding utf8
    Invoke-WithRetry -OperationName "PUT $Label" -Action {
        az rest --method put --url "$Url`?api-version=$ApiVersion" --body "@$tmp" --headers 'Content-Type=application/json' 1>$null
        if ($LASTEXITCODE -ne 0) { throw "PUT $Label failed" }
    }
    Remove-Item $tmp -Force
    Write-Ok "Applied policy: $Label"
}

# ---- Global (service) policy with placeholder substitution ----
$globalXml = Get-Content -Raw -Path (Join-Path $policiesDir 'global-foundry-policy.xml')
$globalXml = $globalXml.
    Replace('{{TOKEN_QUOTA}}',        [string]$params['subscriptionTokenQuota']).
    Replace('{{TOKEN_QUOTA_PERIOD}}', [string]$params['subscriptionTokenQuotaPeriod']).
    Replace('{{TPM_GUARDRAIL}}',      [string]$params['subscriptionTpmGuardrail'])
Set-Policy -Url "$base/policies/policy" -Xml $globalXml -Label 'service/global'

# ---- Per-API policies ----
$apiPolicyMap = @{
    'foundry-gpt5-nano-api' = 'api-foundry-gpt5-nano-policy.xml'
    'foundry-gpt5-mini-api' = 'api-foundry-gpt5-mini-policy.xml'
    'foundry-gpt52-api'     = 'api-foundry-gpt52-policy.xml'
    'foundry-gpt54-api'     = 'api-foundry-gpt54-policy.xml'
    'foundry-embeddings-api'= 'api-foundry-embeddings-policy.xml'
}
foreach ($apiName in $apiPolicyMap.Keys) {
    $file = Join-Path $policiesDir $apiPolicyMap[$apiName]
    if (-not (Test-Path $file)) { Write-Warn2 "Missing $file - skipping $apiName"; continue }
    $xml = Get-Content -Raw -Path $file
    Set-Policy -Url "$base/apis/$apiName/policies/policy" -Xml $xml -Label "api/$apiName"
}

Write-Ok 'All policies applied.'
Write-Info 'Next: ./06-create-products-and-subscriptions.ps1 (optional ensure) or ./07-post-deploy-smoke-tests.ps1'
