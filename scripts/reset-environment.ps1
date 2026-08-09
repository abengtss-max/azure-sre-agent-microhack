# Aetherion AirOps - reset all injected failures back to healthy.

$ErrorActionPreference = "Stop"
$ns = "aetherion"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
$services = @("flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest", "gateway")

Write-Host "Clearing FAULT_MODE on all services..." -ForegroundColor Cyan
foreach ($s in $services) {
    kubectl set env deploy/$s -n $ns FAULT_MODE=none | Out-Null
    Write-Host "  $s -> none" -ForegroundColor Gray
}

# Return the load generator to its normal level (challenges 2 & 7 set surge).
kubectl set env deploy/k6-load -n $ns MODE=normal VUS=25 2>$null | Out-Null
Write-Host "  k6-load -> normal (25 VUs)" -ForegroundColor Gray

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

Write-Host "Waiting for rollouts to settle..." -ForegroundColor Cyan
foreach ($s in $services) { kubectl rollout status deploy/$s -n $ns --timeout=120s | Out-Null }
Write-Host "Environment reset to healthy." -ForegroundColor Green
