# =============================================================================
# scripts/lib/common.ps1  -  Shared helpers: logging, retry, idempotency.
# Dot-source this file from other scripts:  . "$PSScriptRoot/lib/common.ps1"
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info  { param([string]$Message) Write-Host "[INFO ] $Message" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Message) Write-Host "[ OK  ] $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "[WARN ] $Message" -ForegroundColor Yellow }
function Write-Err2  { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Invoke-WithRetry: run a script block with exponential backoff.
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [int] $MaxAttempts = 5,
        [int] $InitialDelaySeconds = 5,
        [string] $OperationName = 'operation'
    )
    $attempt = 0
    $delay = $InitialDelaySeconds
    while ($true) {
        $attempt++
        try {
            return & $Action
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                Write-Err2 "$OperationName failed after $attempt attempts: $($_.Exception.Message)"
                throw
            }
            Write-Warn2 "$OperationName failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
            $delay = [Math]::Min($delay * 2, 60)
        }
    }
}

# Assert a command exists (e.g. az).
function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

# Run an az CLI command (passed as args array) and return parsed JSON.
function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Args)
    $raw = az @Args -o json
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Args -join ' ') failed with exit code $LASTEXITCODE"
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

# Read an ARM-style parameters JSON file into a hashtable of name -> value.
function Read-ParametersFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Parameters file not found: $Path" }
    $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
    $result = @{}
    foreach ($p in $json.parameters.PSObject.Properties) {
        $result[$p.Name] = $p.Value.value
    }
    return $result
}
