# Aetherion AirOps - deploy infrastructure (Bicep)
# Creates the resource group and deploys infra/main.bicep, then saves outputs
# (plus the generated PG password) to scripts/.env.aetherion.json for later steps.

param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [string]$Location = "swedencentral",
    [string]$NamePrefix = "aetherion",
    [int]$AksNodeCount = 3,
    [string]$AksNodeVmSize = "Standard_D4s_v5",
    [ValidateSet("Consumption", "Developer")]
    [string]$ApimSkuName = "Consumption",
    [string]$RedisLocation = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$bicep = Join-Path $repoRoot "infra/main.bicep"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"

Write-Host "Resolving signed-in identity..." -ForegroundColor Cyan
$deployerObjectId = az ad signed-in-user show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($deployerObjectId)) {
    throw "Could not resolve signed-in user object id. Run 'az login' first."
}

# Generate a strong PostgreSQL admin password for this disposable environment.
$pgPassword = "Aeth!" + [System.Guid]::NewGuid().ToString("N").Substring(0, 20) + "9x"

Write-Host "Creating resource group '$ResourceGroup' in $Location..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location | Out-Null

# Self-heal: APIM soft-delete survives resource-group deletion and reserves the
# service name, so a re-run (or a retry after a failed run) would fail with
# 'ServiceAlreadyExistsInSoftDeletedState'. Purge any soft-deleted APIM matching
# this environment's naming before deploying.
$deletedApim = az apim deletedservice list --query "[?starts_with(name, '$NamePrefix-apim')].{name:name, location:location}" -o json 2>$null | ConvertFrom-Json
foreach ($d in $deletedApim) {
    $loc = ($d.location -replace '\s', '').ToLower()
    Write-Host "Purging soft-deleted APIM '$($d.name)' in $loc..." -ForegroundColor Yellow
    az apim deletedservice purge --service-name $d.name --location $loc --only-show-errors 2>$null | Out-Null
}

$deploymentName = "aetherion-infra-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
Write-Host "Deploying infrastructure (a few minutes; APIM Consumption tier provisions fast)..." -ForegroundColor Cyan

$outputsJson = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --template-file $bicep `
    --parameters `
        namePrefix=$NamePrefix `
        location=$Location `
        pgAdminPassword=$pgPassword `
        deployerObjectId=$deployerObjectId `
        aksNodeCount=$AksNodeCount `
        aksNodeVmSize=$AksNodeVmSize `
        apimSkuName=$ApimSkuName `
        redisLocation=$(if ([string]::IsNullOrWhiteSpace($RedisLocation)) { $Location } else { $RedisLocation }) `
    --query properties.outputs -o json

if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed. Review the error above."
}

$outputs = $outputsJson | ConvertFrom-Json
$state = [ordered]@{
    resourceGroup   = $ResourceGroup
    location        = $Location
    namePrefix      = $NamePrefix
    pgAdminPassword = $pgPassword
}
foreach ($k in $outputs.PSObject.Properties.Name) {
    $state[$k] = $outputs.$k.value
}

$state | ConvertTo-Json -Depth 5 | Set-Content -Path $envFile -Encoding UTF8
Write-Host "Infrastructure deployed. State saved to $envFile" -ForegroundColor Green

# Container Insights is enabled AFTER the cluster exists (not inline in Bicep) so
# the AKS create stays fast and never hangs reconciling the monitoring addon.
Write-Host "Enabling Container Insights on AKS..." -ForegroundColor Cyan
az aks enable-addons --resource-group $ResourceGroup --name $state.aksName `
    --addons monitoring --workspace-resource-id $state.logAnalyticsId --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Container Insights not enabled yet - enable later with:" -ForegroundColor Yellow
    Write-Host "  az aks enable-addons -g $ResourceGroup -n $($state.aksName) -a monitoring --workspace-resource-id $($state.logAnalyticsId)" -ForegroundColor Gray
}

Write-Host "  ACR:     $($state.acrLoginServer)" -ForegroundColor Gray
Write-Host "  AKS:     $($state.aksName)" -ForegroundColor Gray
Write-Host "  APIM:    $($state.apimGatewayUrl)" -ForegroundColor Gray
Write-Host "  Grafana: $($state.grafanaEndpoint)" -ForegroundColor Gray
Write-Host "IMPORTANT: .env.aetherion.json contains a password. Do not commit it." -ForegroundColor Yellow
