#Requires -Version 7.0
# Aetherion AirOps - reset all injected failures back to a clean, healthy baseline.
#
# Restores releases, resource limits, autoscaler ceilings and the database
# baseline, removes the APIM backend override, and returns the load generator to
# normal, then verifies the platform reports healthy.
# Use -ResetProgress to ALSO reset the linear challenge unlock gate
# (aetherion-progress) back to 1 for a brand-new run.

param(
    [switch]$ResetProgress
)

$ErrorActionPreference = "Stop"
$ns = "aetherion"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
. (Join-Path $PSScriptRoot 'lib-apim.ps1')
. (Join-Path $PSScriptRoot 'lib-dbjob.ps1')
$services = @("flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest", "gateway")

# Undo the change-shaped faults: release tag, resource limits, pool headroom and
# any canary revision a challenge left behind.
Write-Host "Restoring releases, limits and pool headroom..." -ForegroundColor Cyan
if (Test-Path $envFile) {
    $resetState = Get-Content $envFile -Raw | ConvertFrom-Json
    $goodImage = "$($resetState.acrLoginServer)/aetherion-airops:latest"
    foreach ($s in $services) {
        kubectl set image deploy/$s -n $ns "$s=$goodImage" 2>$null | Out-Null
        kubectl set resources deploy/$s -n $ns -c $s --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi 2>$null | Out-Null
    }
    Write-Host "  images -> :latest, cpu limits -> 500m" -ForegroundColor Gray
}
# PG_POOL_MAX comes from the aetherion-config ConfigMap; drop any deployment override.
kubectl set env deploy/crew-scheduling -n $ns PG_POOL_MAX- 2>$null | Out-Null
foreach ($s in $services) { kubectl delete deploy "$s-v2" -n $ns --ignore-not-found 2>$null | Out-Null }
# Autoscaler bounds: booking runs 2-6, crew-scheduling is capped at 3 by design.
kubectl patch hpa booking -n $ns --type=merge -p (@{ spec = @{ minReplicas = 2; maxReplicas = 6 } } | ConvertTo-Json -Compress) 2>$null | Out-Null
kubectl patch hpa crew-scheduling -n $ns --type=merge -p (@{ spec = @{ minReplicas = 2; maxReplicas = 3 } } | ConvertTo-Json -Compress) 2>$null | Out-Null
Write-Host "  pool override cleared, canary revisions removed, autoscaler ceilings restored" -ForegroundColor Gray

# The platform ships with an index behind the crew duty lookup; a challenge may
# have removed it. Restore it, and clear any maintenance jobs left behind.
kubectl delete jobs -n $ns -l component=db-maintenance --ignore-not-found 2>$null | Out-Null
if (Invoke-AetherionDbSql -Sql 'CREATE INDEX IF NOT EXISTS idx_crew_roster_duty ON crew_roster (assigned, flight_no, crew_member);' -Name 'reset-crew-index') {
    Write-Host "  crew roster index restored" -ForegroundColor Gray
}
else {
    Write-Host "  WARNING: could not restore the crew roster index - crew scheduling will stay slow." -ForegroundColor Yellow
}

# Return the load generator to its normal level (challenges 2 & 7 set surge).
& (Join-Path $PSScriptRoot "deploy-loadgen.ps1") -Mode normal 2>$null | Out-Null
Write-Host "  k6 load -> normal (25 VUs)" -ForegroundColor Gray

if (Test-Path $envFile) {
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    $policy = '<policies><inbound><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    Write-Host "Restoring default APIM product policy..." -ForegroundColor Cyan
    if (-not (Set-AetherionApimProductPolicy -ResourceGroup $state.resourceGroup -ApimName $state.apimName -PolicyXml $policy)) {
        Write-Host "  WARNING: APIM product policy reset failed (a backend override from Challenge 7 may persist)." -ForegroundColor Yellow
    }
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
