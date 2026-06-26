# =============================================================================
# tests/failover-validation.ps1  -  Validate priority backend pool + breaker.
#
# What it checks automatically (read-only):
#   1. Each model-family pool exists and has >1 member ordered by priority
#      (so failover is even possible).
#   2. Each single backend has a circuit-breaker rule configured.
#
# Live failover (tripping the highest-priority region and proving traffic shifts
# to the next) cannot be forced safely/deterministically from the client side
# because circuit-breaker state is per-gateway-instance and approximate
# (https://learn.microsoft.com/azure/api-management/backends). The script prints
# a guided procedure for an operator-driven live test.
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $ApimName,
    [Parameter(Mandatory)] [string] $ParametersFile,
    [string] $ApiVersion = '2024-06-01-preview'
)
. "$PSScriptRoot/../scripts/lib/common.ps1"
Assert-Command 'az'

$params = Read-ParametersFile -Path $ParametersFile
$topology = $params['modelTopology']
$subId = (Invoke-AzJson @('account','show')).id
$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

$fail = 0
foreach ($f in $topology) {
    # ---- Pool composition ----
    $pool = $null
    try { $pool = (az rest --method get --url "$base/backends/$($f.poolName)?api-version=$ApiVersion" -o json | ConvertFrom-Json) } catch {}
    if (-not $pool) { Write-Err2 "Pool $($f.poolName) not found."; $fail++; continue }
    $members = $pool.properties.pool.services
    $priorities = ($members | ForEach-Object { $_.priority } | Sort-Object -Unique)
    if ($f.regions.Count -gt 1 -and $priorities.Count -lt 2) {
        Write-Warn2 "Pool $($f.poolName) has $($members.Count) members but a single priority tier - no failover ordering."
    } else {
        Write-Ok "Pool $($f.poolName): $($members.Count) member(s), priority tiers: $($priorities -join ',')"
    }

    # ---- Circuit breaker on each single backend ----
    foreach ($r in $f.regions) {
        $beName = "be-$($f.key)-$($r.account)"
        $be = $null
        try { $be = (az rest --method get --url "$base/backends/$beName?api-version=$ApiVersion" -o json | ConvertFrom-Json) } catch {}
        if (-not $be) { Write-Err2 "Backend $beName not found."; $fail++; continue }
        $rules = $be.properties.circuitBreaker.rules
        if ($rules -and $rules.Count -ge 1) {
            Write-Ok "Backend $beName has circuit breaker '$($rules[0].name)'."
        } else {
            Write-Err2 "Backend $beName MISSING circuit breaker."
            $fail++
        }
    }
}

Write-Host ''
Write-Info 'Operator-driven LIVE failover test (manual):'
Write-Host '  1. Note the highest-priority region for a model (e.g. swc for gpt5-nano).'
Write-Host '  2. Temporarily make that backend fail: in the portal disable/scale the swc'
Write-Host '     Foundry deployment, OR set its capacity to 0, OR block its endpoint.'
Write-Host '  3. Send sustained requests via the gateway. After the breaker trips'
Write-Host '     (>= failure count within the interval), responses should keep returning 200'
Write-Host '     served by the next-priority region (e.g. eus2).'
Write-Host '  4. Restore the swc deployment; traffic returns after the trip duration.'

if ($fail -gt 0) { Write-Err2 "$fail static failover checks failed."; exit 1 }
Write-Ok 'Static failover configuration checks passed.'
