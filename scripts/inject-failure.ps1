#Requires -Version 7.0
# Aetherion AirOps - inject a failure for a MicroHack challenge.
#
# Usage:
#   ./inject-failure.ps1 -Service crew-scheduling -Fault slow-query
#   ./inject-failure.ps1 -Service booking        -Fault cpu-starve
#   ./inject-failure.ps1 -Service flight-ops     -Fault badimage
#   ./inject-failure.ps1 -Service apim           -Fault bad-backend
#
# The change faults leave no synthetic marker: each one is an ordinary operator
# mistake applied the way a real one would be. The legacy profile faults are
# retained for facilitator use only.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("flight-ops", "crew-scheduling", "booking", "baggage", "telemetry-ingest", "gateway", "apim")]
    [string]$Service,

    [Parameter(Mandatory = $true)]
    [ValidateSet("bad-backend", "badimage", "cpu-starve", "canary", "slow-query")]
    [string]$Fault
)

$ErrorActionPreference = "Stop"
$ns = "aetherion"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
. (Join-Path $PSScriptRoot 'lib-apim.ps1')
. (Join-Path $PSScriptRoot 'lib-dbjob.ps1')

if ($Service -eq "apim") {
    if ($Fault -ne "bad-backend") { throw "For service 'apim', only -Fault bad-backend is supported." }
    if (-not (Test-Path $envFile)) { throw "State file not found. Deploy first." }
    $state = Get-Content $envFile -Raw | ConvertFrom-Json

    # A backend override published to the product policy. The host does not
    # resolve, so the gateway fails every call while the services behind it stay
    # healthy - the signature of an edge-only outage.
    $policy = '<policies><inbound><base /><set-backend-service base-url="http://aetherion-origin-v2.internal" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    Write-Host "Publishing backend override on APIM product 'aetherion-ops'..." -ForegroundColor Yellow
    if (Set-AetherionApimProductPolicy -ResourceGroup $state.resourceGroup -ApimName $state.apimName -PolicyXml $policy) {
        Write-Host "Backend override published. Expect gateway errors while the services stay healthy." -ForegroundColor Green
    }
    else {
        throw "Failed to publish the APIM backend override."
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
    kubectl set resources deploy/$Service -n $ns -c $Service --requests=cpu=10m,memory=128Mi --limits=cpu=50m,memory=256Mi | Out-Null
    kubectl annotate deploy/$Service -n $ns kubernetes.io/change-cause="cost optimisation: reduce cpu request/limit and cap autoscaling" --overwrite | Out-Null
    # The same cost-optimisation change caps how far the service may scale out,
    # so the autoscaler can no longer compensate for the smaller limit.
    $hpaPatch = (@{ spec = @{ maxReplicas = 2 } } | ConvertTo-Json -Compress)
    kubectl patch hpa $Service -n $ns --type=merge -p $hpaPatch 2>$null | Out-Null
    kubectl rollout status deploy/$Service -n $ns --timeout=120s
    Write-Host "CPU limits applied to '$Service'." -ForegroundColor Green
    return
}

if ($Fault -eq "slow-query") {
    # Removes the index behind the crew duty lookup, the way a maintenance script
    # that rebuilds the roster table would. The query still returns correct data,
    # it just falls back to scanning every retained duty record.
    Write-Host "Dropping the crew roster duty index..." -ForegroundColor Yellow
    if (Invoke-AetherionDbSql -Sql 'DROP INDEX IF EXISTS idx_crew_roster_duty;' -Name 'crew-roster-reindex') {
        Write-Host "Crew duty lookup is now unindexed." -ForegroundColor Green
    }
    else {
        throw "Failed to drop the crew roster index."
    }
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

throw "Fault '$Fault' is not supported for service '$Service'. Use one of: badimage, cpu-starve, canary, slow-query (or bad-backend on apim)."
