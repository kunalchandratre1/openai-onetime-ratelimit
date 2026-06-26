# =============================================================================
# tests/product-entitlement-validation.ps1  -  Assert product->API entitlements.
#
# Verifies every product p1..pN is linked to ALL model-family APIs ("all models"
# entitlement design). Fails if any product is missing any API link.
# Ref: https://learn.microsoft.com/rest/api/apimanagement/product-api/list-by-product
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [int] $SampleProducts = 0,   # 0 => check all products; otherwise check first N (faster).
    [string] $ApiVersion = '2024-05-01'
)
. "$PSScriptRoot/../scripts/lib/common.ps1"
Assert-Command 'az'

$params = Read-ParametersFile -Path $ParametersFile
$productCount = [int]$params['productCount']
$expectedApis = @($params['modelTopology'] | ForEach-Object { $_.apiName }) | Sort-Object
$subId = (Invoke-AzJson @('account','show')).id
$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

$limit = if ($SampleProducts -gt 0) { [Math]::Min($SampleProducts, $productCount) } else { $productCount }
$fail = 0

for ($i = 1; $i -le $limit; $i++) {
    $pid = "p$i"
    $linked = @()
    try {
        $resp = az rest --method get --url "$base/products/$pid/apis?api-version=$ApiVersion" -o json | ConvertFrom-Json
        $linked = @($resp.value | ForEach-Object { $_.name }) | Sort-Object
    } catch {
        Write-Err2 "$pid : could not list linked APIs ($($_.Exception.Message))"
        $fail++; continue
    }
    $missing = $expectedApis | Where-Object { $_ -notin $linked }
    if ($missing.Count -eq 0) {
        Write-Ok "$pid linked to all $($expectedApis.Count) APIs."
    } else {
        Write-Err2 "$pid MISSING APIs: $($missing -join ', ')"
        $fail++
    }
}

if ($fail -gt 0) { Write-Err2 "$fail product(s) failed entitlement validation."; exit 1 }
Write-Ok "All $limit checked product(s) have full model entitlement."
