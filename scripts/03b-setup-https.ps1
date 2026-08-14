#Requires -Version 7.0
# Aetherion AirOps - enable HTTPS on the gateway domain.
#
# Modern, non-nginx TLS: cert-manager + Let's Encrypt + Envoy Gateway (Gateway API).
#   - Envoy Gateway terminates TLS at a public LoadBalancer that carries the
#     sreagenthack-<random> DNS label -> <label>.<region>.cloudapp.azure.com
#   - cert-manager auto-issues (and auto-renews) a Let's Encrypt certificate for
#     that hostname via an HTTP-01 challenge solved through the same Gateway.
#   - An HTTPRoute forwards traffic to the existing in-cluster `gateway` service.
#
# ingress-nginx is being retired, so this uses the CNCF Gateway API instead.

param(
    [string]$AcmeEmail = "sre-microhack@aetherion-airops.com",
    [switch]$Staging,          # use Let's Encrypt staging (untrusted) to avoid rate limits while testing
    [string]$EnvoyVersion = "v1.2.6",
    [string]$CertManagerVersion = "v1.16.2"
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$envFile = Join-Path $here ".env.aetherion.json"
if (-not (Test-Path $envFile)) { throw "State file not found. Run 03-deploy-app.ps1 first." }
$state = Get-Content $envFile -Raw | ConvertFrom-Json
$ns = "aetherion"
$region = $state.location

foreach ($tool in @("kubectl", "helm")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is not installed or not on PATH. Install it and retry."
    }
}

# --- Fresh random DNS label for the HTTPS endpoint ---------------------------
$dnsLabel = "sreagenthack-" + (Get-Random -Minimum 10000 -Maximum 99999)
$fqdn = "$dnsLabel.$region.cloudapp.azure.com"
$acmeServer = if ($Staging) {
    "https://acme-staging-v02.api.letsencrypt.org/directory"
} else {
    "https://acme-v02.api.letsencrypt.org/directory"
}
Write-Host "HTTPS host : $fqdn" -ForegroundColor Gray
Write-Host "ACME server: $acmeServer" -ForegroundColor Gray

# --- Install Envoy Gateway first (it installs the Gateway API CRDs) ----------
# cert-manager with Gateway API support won't start unless the Gateway API CRDs
# already exist, so Envoy Gateway must be installed before cert-manager.
Write-Host "Installing Envoy Gateway ($EnvoyVersion)..." -ForegroundColor Cyan
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm `
    --version $EnvoyVersion `
    --namespace envoy-gateway-system --create-namespace `
    --wait --timeout 8m
if ($LASTEXITCODE -ne 0) { throw "Envoy Gateway install failed." }
kubectl rollout status deployment/envoy-gateway -n envoy-gateway-system --timeout=180s

# --- Install cert-manager (with Gateway API support) -------------------------
Write-Host "Installing cert-manager ($CertManagerVersion)..." -ForegroundColor Cyan
helm repo add jetstack https://charts.jetstack.io --force-update | Out-Null
helm repo update | Out-Null
helm upgrade --install cert-manager jetstack/cert-manager `
    --namespace cert-manager --create-namespace `
    --version $CertManagerVersion `
    --set crds.enabled=true `
    --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" `
    --set config.kind="ControllerConfiguration" `
    --set config.enableGatewayAPI=true `
    --wait --timeout 8m
if ($LASTEXITCODE -ne 0) { throw "cert-manager install failed." }

# --- Apply Gateway API + cert-manager resources ------------------------------
Write-Host "Configuring Gateway, issuer and route..." -ForegroundColor Cyan
$yaml = @"
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: aetherion-gw
  namespace: $ns
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  gatewayClassName: eg
  infrastructure:
    annotations:
      service.beta.kubernetes.io/azure-dns-label-name: $dnsLabel
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "$fqdn"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: aetherion-tls
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: $acmeServer
    email: $AcmeEmail
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: aetherion-gw
                namespace: $ns
                kind: Gateway
                group: gateway.networking.k8s.io
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-route
  namespace: $ns
spec:
  parentRefs:
    - name: aetherion-gw
  hostnames:
    - "$fqdn"
  rules:
    - backendRefs:
        - name: gateway
          port: 80
"@
$tmp = Join-Path $env:TEMP "aetherion-https.yaml"
$yaml | Set-Content -Path $tmp -Encoding UTF8
kubectl apply -f $tmp
if ($LASTEXITCODE -ne 0) { throw "Failed to apply HTTPS resources." }

# --- Wait for the Gateway public IP so the DNS label resolves ----------------
Write-Host "Waiting for Gateway public IP + DNS label..." -ForegroundColor Cyan
$gwIp = ""
for ($i = 0; $i -lt 30; $i++) {
    $gwIp = kubectl get gateway aetherion-gw -n $ns -o jsonpath='{.status.addresses[0].value}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($gwIp)) { break }
    Start-Sleep -Seconds 10
}
if ([string]::IsNullOrWhiteSpace($gwIp)) { throw "Gateway public IP not assigned in time." }
Write-Host "Gateway public IP: $gwIp" -ForegroundColor Green

# --- Wait for the Let's Encrypt certificate to be issued ---------------------
Write-Host "Waiting for Let's Encrypt certificate (this can take a couple of minutes)..." -ForegroundColor Cyan
$issued = $false
for ($i = 0; $i -lt 40; $i++) {
    $crt = kubectl get secret aetherion-tls -n $ns -o jsonpath='{.data.tls\.crt}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($crt)) { $issued = $true; break }
    Start-Sleep -Seconds 15
}
if (-not $issued) {
    Write-Host "Certificate not issued yet. Inspect with:" -ForegroundColor Yellow
    Write-Host "  kubectl describe certificate -n $ns" -ForegroundColor Yellow
    Write-Host "  kubectl describe challenge -n $ns" -ForegroundColor Yellow
    throw "Certificate was not issued in time."
}
Write-Host "Certificate issued." -ForegroundColor Green

# --- Persist + report ---------------------------------------------------------
$httpsUrl = "https://$fqdn/"
$state | Add-Member -NotePropertyName dnsLabel -NotePropertyValue $dnsLabel -Force
$state | Add-Member -NotePropertyName gatewayFqdn -NotePropertyValue $fqdn -Force
$state | Add-Member -NotePropertyName httpsUrl -NotePropertyValue $httpsUrl -Force
$state | Add-Member -NotePropertyName httpsGatewayIp -NotePropertyValue $gwIp -Force
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $envFile -Encoding UTF8

Write-Host "HTTPS is live." -ForegroundColor Green
Write-Host "  Ops Center (HTTPS): $httpsUrl" -ForegroundColor Gray
Write-Host "  Public IP:          $gwIp" -ForegroundColor Gray
