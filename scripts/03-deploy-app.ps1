# Aetherion AirOps - deploy the application to AKS and wire up APIM + k6
# Fetches secrets, creates the k8s secret, deploys manifests, waits for the
# gateway public IP, points APIM at it, and starts the k6 load generator.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"
if (-not (Test-Path $envFile)) { throw "State file not found. Run 01-deploy-infra.ps1 first." }
$state = Get-Content $envFile -Raw | ConvertFrom-Json
$rg = $state.resourceGroup
$ns = "aetherion"

Write-Host "Getting AKS credentials..." -ForegroundColor Cyan
az aks get-credentials --resource-group $rg --name $state.aksName --overwrite-existing | Out-Null

Write-Host "Fetching connection secrets..." -ForegroundColor Cyan
$appiConn = az resource show --resource-group $rg --name $state.appInsightsName `
    --resource-type "Microsoft.Insights/components" --query "properties.ConnectionString" -o tsv

Write-Host "Creating namespace and secret..." -ForegroundColor Cyan
kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aetherion-secrets -n $ns `
    --from-literal=PGHOST=$($state.pgFqdn) `
    --from-literal=PGUSER=$($state.pgAdminLogin) `
    --from-literal=PGPASSWORD=$($state.pgAdminPassword) `
    --from-literal=REDIS_HOST=redis `
    --from-literal=REDIS_PASSWORD="" `
    --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING=$appiConn `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Applying application manifests..." -ForegroundColor Cyan
Write-Host "Applying application manifests..." -ForegroundColor Cyan
$manifest = Get-Content (Join-Path $repoRoot "k8s/aetherion-airops.yaml") -Raw
$manifest = $manifest.Replace("REPLACE_ACR", $state.acrLoginServer)
$tmp = Join-Path $env:TEMP "aetherion-airops.rendered.yaml"
$manifest | Set-Content -Path $tmp -Encoding UTF8
kubectl apply -f $tmp

Write-Host "Waiting for deployments to become available..." -ForegroundColor Cyan
kubectl rollout status deploy/gateway -n $ns --timeout=300s

Write-Host "Waiting for gateway public IP..." -ForegroundColor Cyan
$gwIp = ""
for ($i = 0; $i -lt 60; $i++) {
    $gwIp = kubectl get svc gateway -n $ns -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace($gwIp)) { break }
    Start-Sleep -Seconds 10
}
if ([string]::IsNullOrWhiteSpace($gwIp)) { throw "Gateway public IP not assigned in time." }
Write-Host "Gateway public IP: $gwIp" -ForegroundColor Green

Write-Host "Pointing APIM at the gateway..." -ForegroundColor Cyan
az apim api update --resource-group $rg --service-name $state.apimName `
    --api-id aetherion --set serviceUrl="http://$gwIp" | Out-Null

Write-Host "Reading APIM subscription key..." -ForegroundColor Cyan
$subId = az account show --query id -o tsv
$secretUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$($state.apimName)/subscriptions/aetherion-ops-sub/listSecrets?api-version=2022-08-01"
$apiKey = az rest --method post --uri $secretUri --query primaryKey -o tsv

# Persist wiring for validation + fault scripts
$state | Add-Member -NotePropertyName gatewayIp -NotePropertyValue $gwIp -Force
$state | Add-Member -NotePropertyName apimSubscriptionKey -NotePropertyValue $apiKey -Force
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $envFile -Encoding UTF8

Write-Host "Starting k6 load generator on ACI (outside the monitored resource group)..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "deploy-loadgen.ps1") -ResourceGroup $rg -Location $state.location -Mode normal

Write-Host "Application deployed and load started." -ForegroundColor Green
Write-Host "  Ops Center (direct): http://$gwIp/" -ForegroundColor Gray
Write-Host "  API via APIM:        $($state.apimGatewayUrl)/aetherion/api/status" -ForegroundColor Gray
Write-Host "  Grafana:             $($state.grafanaEndpoint)" -ForegroundColor Gray
