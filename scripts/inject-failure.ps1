#Requires -Version 7.0
# Aetherion AirOps - inject a failure for a MicroHack challenge.
#
# Usage:
#   ./inject-failure.ps1 -Service crew-scheduling -Fault db-pool
#   ./inject-failure.ps1 -Service booking        -Fault latency
#   ./inject-failure.ps1 -Service flight-ops     -Fault crash
#   ./inject-failure.ps1 -Service apim           -Fault throttle
#
# App behaviour is controlled by an opaque service profile so the deployment env
# never names the fault. The mapping (kept in sync with app/src/server.js) is:
#   standard=none  r1=latency  r2=error  r3=crash  r4=memory  r5=db-pool
# Special target 'apim' applies a restrictive rate-limit policy instead.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest", "gateway", "apim")]
    [string]$Service,

    [Parameter(Mandatory = $true)]
    [ValidateSet("none", "latency", "error", "crash", "memory", "db-pool", "throttle")]
    [string]$Fault
)

$ErrorActionPreference = "Stop"
$ns = "aetherion"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
. (Join-Path $PSScriptRoot 'lib-apim.ps1')

if ($Service -eq "apim") {
    if ($Fault -ne "throttle") { throw "For service 'apim', only -Fault throttle is supported." }
    if (-not (Test-Path $envFile)) { throw "State file not found. Deploy first." }
    $state = Get-Content $envFile -Raw | ConvertFrom-Json

    $policy = '<policies><inbound><base /><rate-limit-by-key calls="5" renewal-period="60" counter-key="@(context.Subscription.Id)" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    Write-Host "Applying restrictive rate-limit (5 calls / 60s) on APIM product 'aetherion-ops'..." -ForegroundColor Yellow
    if (Set-AetherionApimProductPolicy -ResourceGroup $state.resourceGroup -ApimName $state.apimName -PolicyXml $policy) {
        Write-Host "APIM throttle injected. Expect HTTP 429 under load." -ForegroundColor Green
    }
    else {
        throw "Failed to apply APIM throttle policy."
    }
    return
}

# Map the internal fault name to the opaque profile the app actually reads.
$profileFor = @{ 'none' = 'standard'; 'latency' = 'r1'; 'error' = 'r2'; 'crash' = 'r3'; 'memory' = 'r4'; 'db-pool' = 'r5' }
$profile = $profileFor[$Fault]
Write-Host "Setting service profile '$profile' on deployment '$Service'..." -ForegroundColor Yellow
kubectl set env deploy/$Service -n $ns SVC_PROFILE=$profile
if ($Fault -eq "crash") {
    # A crash fault fails liveness/readiness by design, so the rollout never
    # reaches Ready - don't block on `rollout status` (it would wait the full
    # timeout). The service is meant to go down; give Kubernetes a moment.
    Write-Host "Crash fault set - pods will fail health checks and the service goes down." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
} else {
    kubectl rollout status deploy/$Service -n $ns --timeout=120s
}
Write-Host "Fault '$Fault' injected into '$Service'." -ForegroundColor Green
