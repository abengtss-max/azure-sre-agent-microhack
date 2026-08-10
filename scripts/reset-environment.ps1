# Aetherion AirOps - reset all injected failures back to a clean, healthy baseline.
#
# Clears every app FAULT_MODE, removes the APIM throttle policy, and returns the
# load generator to normal, then verifies the platform reports healthy.
# Use -ResetProgress to ALSO reset the linear challenge unlock gate
# (aetherion-progress) back to 1 for a brand-new run.

param(
    [switch]$ResetProgress
)

$ErrorActionPreference = "Stop"
$ns = "aetherion"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
$services = @("flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest", "gateway")

Write-Host "Clearing FAULT_MODE on all services..." -ForegroundColor Cyan
foreach ($s in $services) {
    # Keep going if one deployment is missing; a partial estate should still reset.
    kubectl set env deploy/$s -n $ns FAULT_MODE=none 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  $s -> none" -ForegroundColor Gray }
    else { Write-Host "  $s -> skipped (deployment not found)" -ForegroundColor DarkYellow }
}

# Return the load generator to its normal level (challenges 2 & 7 set surge).
& (Join-Path $PSScriptRoot "deploy-loadgen.ps1") -Mode normal 2>$null | Out-Null
Write-Host "  k6 load -> normal (25 VUs)" -ForegroundColor Gray

if (Test-Path $envFile) {
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    $policy = @"
<policies>
  <inbound><base /></inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
"@
    $tmp = Join-Path $env:TEMP "apim-reset-policy.xml"
    $policy | Set-Content -Path $tmp -Encoding UTF8
    Write-Host "Restoring default APIM product policy..." -ForegroundColor Cyan
    az apim product policy create --resource-group $state.resourceGroup --service-name $state.apimName `
        --product-id aetherion-ops --policy-file $tmp --policy-format xml | Out-Null
}

# Optionally reset the linear challenge unlock gate for a fresh run.
if ($ResetProgress) {
    Write-Host "Resetting challenge progress (aetherion-progress -> unlocked=1)..." -ForegroundColor Cyan
    kubectl create configmap aetherion-progress -n $ns --from-literal=unlocked=1 `
        --dry-run=client -o yaml 2>$null | kubectl apply -f - 2>$null | Out-Null
}

Write-Host "Waiting for rollouts to settle..." -ForegroundColor Cyan
foreach ($s in $services) { kubectl rollout status deploy/$s -n $ns --timeout=120s 2>$null | Out-Null }

# Best-effort health verification so "reset to healthy" is trustworthy.
$healthy = $true
$overall = 'unknown'
if (Test-Path $envFile) {
    try {
        $st = Get-Content $envFile -Raw | ConvertFrom-Json
        if ($st.gatewayIp) {
            $status = Invoke-RestMethod -Uri "http://$($st.gatewayIp)/api/status" -TimeoutSec 15
            $overall = $status.overall
            foreach ($p in $status.services.PSObject.Properties) { if (-not $p.Value.ok) { $healthy = $false } }
        }
    } catch { $healthy = $false }
}

if ($healthy) {
    Write-Host "Environment reset to healthy." -ForegroundColor Green
}
else {
    Write-Host "Reset applied, but health is not all-green yet (overall=$overall). Give it a minute, then re-check with ./scripts/04-validate.ps1." -ForegroundColor Yellow
}
