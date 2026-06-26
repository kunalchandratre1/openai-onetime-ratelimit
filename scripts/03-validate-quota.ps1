# =============================================================================
# 03-validate-quota.ps1  -  Pre-flight Foundry/OpenAI quota check (read-only).
#
# Foundry quota is REGIONAL, per-subscription, per-model/deployment-type
# (https://learn.microsoft.com/azure/ai-foundry/openai/quotas-limits). This
# script lists current usage/limits per region and prints the capacity this repo
# intends to request, so you can confirm headroom BEFORE deploying.
#
# It is intentionally NON-BLOCKING: model usage metric names vary, so it reports
# rather than hard-fails. Review the output and request quota increases if needed.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ParametersFile
)
. "$PSScriptRoot/lib/common.ps1"
Assert-Command 'az'

$params = Read-ParametersFile -Path $ParametersFile
$accounts = $params['foundryAccounts']
$capacities = $params['capacities']

# Build region -> { location, requested:[{model,capacity}] }
$byRegionKey = @{}
foreach ($a in $accounts.PSObject.Properties) {
    $byRegionKey[$a.Name] = [ordered]@{ location = $a.Value.location; requested = @() }
}
foreach ($c in $capacities.PSObject.Properties) {
    $parts = $c.Name -split '_', 2
    $regionKey = $parts[0]
    $modelKey  = $parts[1]
    if ($byRegionKey.ContainsKey($regionKey)) {
        $byRegionKey[$regionKey].requested += [pscustomobject]@{ model = $modelKey; capacity = [int]$c.Value }
    }
}

foreach ($rk in $byRegionKey.Keys) {
    $loc = $byRegionKey[$rk].location
    Write-Host ''
    Write-Info "Region '$rk' ($loc)"
    $totalUnits = ($byRegionKey[$rk].requested | Measure-Object -Property capacity -Sum).Sum
    foreach ($r in $byRegionKey[$rk].requested) {
        Write-Host ("    requested: {0,-24} {1} TPM-units (= {2:N0} TPM)" -f $r.model, $r.capacity, ($r.capacity * 1000))
    }
    Write-Host ("    --> total requested in {0}: {1} units" -f $loc, $totalUnits)

    Write-Info "Current OpenAI usage/limits reported for $loc :"
    try {
        $usages = Invoke-AzJson @('cognitiveservices','usage','list','--location',$loc)
        if ($usages) {
            $usages |
                Where-Object { $_.name.value -match 'OpenAI|gpt|embedding' } |
                ForEach-Object {
                    Write-Host ("    usage: {0,-48} current={1} limit={2}" -f $_.name.value, $_.currentValue, $_.limit)
                }
        } else {
            Write-Warn2 "    No usage data returned for $loc (provider may not expose it via this API in your tenant)."
        }
    }
    catch {
        Write-Warn2 "    Could not list usage for $loc : $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Warn2 'Review the above. If requested capacity exceeds available limit for any model/region, request an increase via https://aka.ms/oai/stuquotarequest before deploying.'
Write-Info 'Next: ./04-deploy-infra.ps1 -ResourceGroup <rg> -Location <loc> -ParametersFile ' + $ParametersFile
