# =============================================================================
# 06-create-products-and-subscriptions.ps1  -  Idempotent ensure of products,
# product->API links, and subscriptions, driven by the parameters file.
#
# main.bicep creates these too. Use THIS script to scale counts up/down
# (e.g. change productCount / subscriptionsPerProduct in the params file) and
# converge WITHOUT a full bicep redeploy. All operations are PUT (upsert).
#
# Naming convention: products p1..pN ; subscriptions p{i}subscriptionteam{j}.
# Ref: https://learn.microsoft.com/rest/api/apimanagement/product/create-or-update
#      https://learn.microsoft.com/rest/api/apimanagement/product-api/create-or-update
#      https://learn.microsoft.com/rest/api/apimanagement/subscription/create-or-update
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $ApiVersion = '2024-05-01'
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$params  = Read-ParametersFile -Path $ParametersFile
$productCount = [int]$params['productCount']
$subsPer      = [int]$params['subscriptionsPerProduct']
$apiNames = @($params['modelTopology'] | ForEach-Object { $_.apiName })

$subId = (Invoke-AzJson @('account','show')).id
$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

function Invoke-Put {
    param([string]$Url, $BodyObject, [string]$Label)
    $args = @('rest','--method','put','--url',"$Url`?api-version=$ApiVersion")
    if ($BodyObject) {
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value ($BodyObject | ConvertTo-Json -Depth 6) -Encoding utf8
        $args += @('--body',"@$tmp",'--headers','Content-Type=application/json')
    }
    Invoke-WithRetry -OperationName "PUT $Label" -Action {
        az @args 1>$null
        if ($LASTEXITCODE -ne 0) { throw "PUT $Label failed" }
    }
    if ($tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

Write-Info "Ensuring $productCount products, each linked to $($apiNames.Count) APIs, with $subsPer subscriptions each..."

for ($i = 1; $i -le $productCount; $i++) {
    $pid = "p$i"
    Invoke-Put -Url "$base/products/$pid" -Label "product/$pid" -BodyObject @{
        properties = @{
            displayName          = $pid
            description          = "Foundry entitlement product $pid (all model families)."
            subscriptionRequired = $true
            approvalRequired     = $false
            state                = 'published'
        }
    }

    foreach ($apiName in $apiNames) {
        # Empty-body PUT creates the product<->API association (idempotent).
        Invoke-Put -Url "$base/products/$pid/apis/$apiName" -Label "$pid<->$apiName" -BodyObject $null
    }

    for ($j = 1; $j -le $subsPer; $j++) {
        $subName = "${pid}subscriptionteam$j"
        Invoke-Put -Url "$base/subscriptions/$subName" -Label "subscription/$subName" -BodyObject @{
            properties = @{
                displayName = $subName
                scope       = "/products/$pid"
                state       = 'active'
            }
        }
    }
    Write-Ok "Converged $pid (+$subsPer subscriptions)."
}

Write-Ok "Done. Total subscriptions ensured: $($productCount * $subsPer)."
Write-Info 'Next: ./07-post-deploy-smoke-tests.ps1'
