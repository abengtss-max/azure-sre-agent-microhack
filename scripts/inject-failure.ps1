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
    [ValidateSet("none", "latency", "error", "crash", "memory", "db-pool", "throttle", "badimage", "cpu-starve", "canary")]
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

# --- Real-world change faults -------------------------------------------------
# These leave no synthetic marker on the workload: they are ordinary operator
# mistakes (a release pinned to a tag that was never pushed, a resource limit cut
# too far, a canary rolled out with the wrong role), so the estate looks exactly
# like a real incident rather than a lab.

if ($Fault -eq "badimage") {
    if (-not (Test-Path $envFile)) { throw "State file not found. Deploy first." }
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    $badTag = "$($state.acrLoginServer)/aetherion-airops:v2.4.1"
    Write-Host "Rolling '$Service' to release $badTag..." -ForegroundColor Yellow
    kubectl set image deploy/$Service -n $ns "$Service=$badTag" | Out-Null
    kubectl annotate deploy/$Service -n $ns kubernetes.io/change-cause="release v2.4.1" --overwrite | Out-Null
    Start-Sleep -Seconds 5
    Write-Host "Release rolled out. Pods cannot pull the new tag." -ForegroundColor Green
    return
}

if ($Fault -eq "cpu-starve") {
    Write-Host "Applying tightened CPU limits to '$Service'..." -ForegroundColor Yellow
    kubectl set resources deploy/$Service -n $ns -c $Service --requests=cpu=25m,memory=128Mi --limits=cpu=50m,memory=256Mi | Out-Null
    kubectl annotate deploy/$Service -n $ns kubernetes.io/change-cause="cost optimisation: reduce cpu request/limit and cap autoscaling" --overwrite | Out-Null
    # The same cost-optimisation change caps how far the service may scale out,
    # so the autoscaler can no longer compensate for the smaller limit.
    $hpaPatch = (@{ spec = @{ maxReplicas = 2 } } | ConvertTo-Json -Compress)
    kubectl patch hpa $Service -n $ns --type=merge -p $hpaPatch 2>$null | Out-Null
    kubectl rollout status deploy/$Service -n $ns --timeout=120s
    Write-Host "CPU limits applied to '$Service'." -ForegroundColor Green
    return
}

if ($Fault -eq "canary") {
    if (-not (Test-Path $envFile)) { throw "State file not found. Deploy first." }
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    # A second revision behind the same Service, rolled out with the wrong ROLE.
    # Its pods pass health checks but serve the wrong API surface, so a slice of
    # traffic fails while the rest succeeds.
    $canary = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $Service-v2
  namespace: $ns
  labels: { app: $Service, tier: service, track: canary }
  annotations: { kubernetes.io/change-cause: "canary rollout v2" }
spec:
  replicas: 1
  selector: { matchLabels: { app: $Service, track: canary } }
  template:
    metadata:
      labels: { app: $Service, tier: service, track: canary }
    spec:
      containers:
        - name: $Service
          image: $($state.acrLoginServer)/aetherion-airops:latest
          ports: [{ containerPort: 8080 }]
          envFrom: [{ configMapRef: { name: aetherion-config } }]
          env:
            - { name: ROLE, value: "telemetry-ingest" }
            - { name: APPLICATIONINSIGHTS_CONNECTION_STRING, valueFrom: { secretKeyRef: { name: aetherion-secrets, key: APPLICATIONINSIGHTS_CONNECTION_STRING } } }
          readinessProbe: { httpGet: { path: /health/ready, port: 8080 }, initialDelaySeconds: 5, periodSeconds: 10 }
          livenessProbe: { httpGet: { path: /health/live, port: 8080 }, initialDelaySeconds: 10, periodSeconds: 10 }
          resources: { requests: { cpu: "100m", memory: "128Mi" }, limits: { cpu: "500m", memory: "256Mi" } }
"@
    Write-Host "Rolling out canary '$Service-v2'..." -ForegroundColor Yellow
    $canary | kubectl apply -f - | Out-Null
    kubectl rollout status deploy/$Service-v2 -n $ns --timeout=120s
    Write-Host "Canary '$Service-v2' is serving traffic alongside '$Service'." -ForegroundColor Green
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
