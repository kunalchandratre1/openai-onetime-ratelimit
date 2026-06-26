# =============================================================================
# 09-rollback.ps1  -  Roll back APIM artifacts (and optionally the whole RG).
#
# Modes:
#   -Mode Policies       Reset global + per-API policies to default (<base/> only).
#   -Mode Artifacts      Delete subscriptions, products, APIs, and backends/pools.
#   -Mode Full           Everything in Artifacts. Add -DeleteResourceGroup to also
#                        delete the resource group (DESTRUCTIVE; requires -Confirm).
#
# All deletes are idempotent (404 is treated as already-gone). Foundry model
# deployments and accounts are left intact unless you delete the resource group.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [ValidateSet('Policies','Artifacts','Full')] [string] $Mode = 'Artifacts',
    [switch] $DeleteResourceGroup,
    [switch] $Confirm,
    [string] $ApiVersion = '2024-05-01'
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$params = Read-ParametersFile -Path $ParametersFile
$productCount = [int]$params['productCount']
$subsPer      = [int]$params['subscriptionsPerProduct']
$topology     = $params['modelTopology']
$apiNames     = @($topology | ForEach-Object { $_.apiName })
$poolNames    = @($topology | ForEach-Object { $_.poolName })

$subId = (Invoke-AzJson @('account','show')).id
$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

$defaultPolicy = @'
<policies>
  <inbound><base /></inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@

function Invoke-Delete {
    param([string]$Url, [string]$Label)
    try {
        az rest --method delete --url "$Url`?api-version=$ApiVersion" 1>$null 2>$null
        Write-Ok "Deleted $Label"
    } catch {
        Write-Warn2 "Skip $Label ($($_.Exception.Message))"
    }
}

function Reset-Policy {
    param([string]$Url, [string]$Label)
    $body = @{ properties = @{ format = 'rawxml'; value = $defaultPolicy } } | ConvertTo-Json -Depth 5
    $tmp = New-TemporaryFile; Set-Content -Path $tmp -Value $body -Encoding utf8
    az rest --method put --url "$Url`?api-version=$ApiVersion" --body "@$tmp" --headers 'Content-Type=application/json' 1>$null 2>$null
    Remove-Item $tmp -Force
    Write-Ok "Reset policy $Label"
}

# ---- Policies (all modes touch these) ----
Write-Info 'Resetting policies to default...'
Reset-Policy -Url "$base/policies/policy" -Label 'service/global'
foreach ($apiName in $apiNames) { Reset-Policy -Url "$base/apis/$apiName/policies/policy" -Label "api/$apiName" }

if ($Mode -eq 'Policies') { Write-Ok 'Policy rollback complete.'; return }

# ---- Subscriptions ----
Write-Info 'Deleting subscriptions...'
for ($i = 1; $i -le $productCount; $i++) {
    for ($j = 1; $j -le $subsPer; $j++) {
        Invoke-Delete -Url "$base/subscriptions/p${i}subscriptionteam$j" -Label "subscription p${i}subscriptionteam$j"
    }
}

# ---- Products ----
Write-Info 'Deleting products...'
for ($i = 1; $i -le $productCount; $i++) {
    Invoke-Delete -Url "$base/products/p$i`?deleteSubscriptions=true" -Label "product p$i"
}

# ---- APIs ----
Write-Info 'Deleting APIs...'
foreach ($apiName in $apiNames) { Invoke-Delete -Url "$base/apis/$apiName" -Label "api $apiName" }

# ---- Backends + pools ----
Write-Info 'Deleting backend pools and backends...'
foreach ($pool in $poolNames) { Invoke-Delete -Url "$base/backends/$pool" -Label "pool $pool" }
foreach ($f in $topology) {
    foreach ($r in $f.regions) {
        Invoke-Delete -Url "$base/backends/be-$($f.key)-$($r.account)" -Label "backend be-$($f.key)-$($r.account)"
    }
}

Write-Ok 'APIM artifact rollback complete.'

if ($Mode -eq 'Full' -and $DeleteResourceGroup) {
    if (-not $Confirm) {
        Write-Warn2 'Refusing to delete resource group without -Confirm. Re-run with -Confirm to proceed.'
        return
    }
    Write-Warn2 "DELETING resource group '$ResourceGroup' (includes Foundry accounts & deployments)..."
    az group delete -n $ResourceGroup --yes --no-wait
    Write-Ok 'Resource group deletion started (no-wait).'
}
