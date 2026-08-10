# Aetherion AirOps - validate the running environment end to end.

[CmdletBinding()]
param(
    [string]$ResourceGroup
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
if (-not (Test-Path $envFile)) {
    if ($ResourceGroup) {
        throw "State file not found at '$envFile'. Re-provision this environment first (resource group: '$ResourceGroup')."
    }
    throw "State file not found at '$envFile'. Run the deploy scripts first."
}
$state = Get-Content $envFile -Raw | ConvertFrom-Json

if (-not $ResourceGroup) {
    $ResourceGroup = $state.resourceGroup
}

if (-not [string]::IsNullOrWhiteSpace($ResourceGroup) -and -not [string]::IsNullOrWhiteSpace($state.resourceGroup)) {
    if ($ResourceGroup -ne $state.resourceGroup) {
        throw "Requested -ResourceGroup '$ResourceGroup' does not match state resource group '$($state.resourceGroup)' in .env.aetherion.json. Use the matching resource group or re-provision."
    }
}

$ns = "aetherion"
$fail = 0

function Check($name, [scriptblock]$test) {
    try {
        if (& $test) { Write-Host "  [PASS] $name" -ForegroundColor Green }
        else { Write-Host "  [FAIL] $name" -ForegroundColor Red; $script:fail++ }
    } catch {
        Write-Host "  [FAIL] $name ($($_.Exception.Message))" -ForegroundColor Red; $script:fail++
    }
}

Write-Host "Validating Aetherion AirOps environment..." -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    Write-Host "  Resource group: $ResourceGroup" -ForegroundColor Gray
}

Check "All app deployments available" {
    $svcs = @("gateway", "flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest")
    foreach ($s in $svcs) {
        $ready = kubectl get deploy $s -n $ns -o jsonpath='{.status.availableReplicas}' 2>$null
        if ([string]::IsNullOrWhiteSpace($ready) -or [int]$ready -lt 1) { return $false }
    }
    return $true
}

Check "k6 load generator running" {
    $ready = kubectl get deploy k6-load -n $ns -o jsonpath='{.status.availableReplicas}' 2>$null
    return (-not [string]::IsNullOrWhiteSpace($ready) -and [int]$ready -ge 1)
}

Check "Gateway reachable directly (HTTP 200 on /api/status)" {
    $r = Invoke-WebRequest -Uri "http://$($state.gatewayIp)/api/status" -UseBasicParsing -TimeoutSec 15
    return $r.StatusCode -eq 200
}

Check "APIM routes to backend (HTTP 200 on /aetherion/api/status)" {
    $headers = @{ "Ocp-Apim-Subscription-Key" = $state.apimSubscriptionKey }
    $r = Invoke-WebRequest -Uri "$($state.apimGatewayUrl)/aetherion/api/status" -Headers $headers -UseBasicParsing -TimeoutSec 20
    return $r.StatusCode -eq 200
}

Check "PostgreSQL reachable from booking pod (readiness ok)" {
    $ready = kubectl get deploy booking -n $ns -o jsonpath='{.status.readyReplicas}' 2>$null
    return (-not [string]::IsNullOrWhiteSpace($ready) -and [int]$ready -ge 1)
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "All checks passed. Environment is healthy." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$fail check(s) failed. Inspect with: kubectl get pods -n $ns" -ForegroundColor Red
    exit 1
}
