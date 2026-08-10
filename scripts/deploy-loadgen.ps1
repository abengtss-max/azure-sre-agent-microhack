# Aetherion AirOps - run the k6 load generator OUTSIDE the monitored environment.
#
# Why: the Azure SRE Agent can inspect the hack AKS cluster and its resource group.
# If k6 runs as an in-cluster pod, the agent can see the load is synthetic. This
# script instead runs k6 as an Azure Container Instance in a SEPARATE, un-monitored
# resource group. It drives the SAME public APIM gateway as real external traffic,
# so from the monitored blast radius there is no visible load generator.
#
# Surge control (replaces `kubectl set env deploy/k6-load MODE=surge`):
#   Normal:  ./deploy-loadgen.ps1 -Mode normal
#   Surge:   ./deploy-loadgen.ps1 -Mode surge
# Each call recreates the container instance with the requested profile.

param(
    # Hack resource group - source of the gateway URL + APIM key (from state file).
    [string]$ResourceGroup = "rg-aetherion-microhack",
    # Separate resource group for the load generator (NOT monitored by the agent).
    [string]$LoadGenResourceGroup = "rg-aetherion-loadgen",
    [string]$Location = "swedencentral",
    [ValidateSet("normal", "surge")]
    [string]$Mode = "normal",
    [int]$Vus = 0
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
$envFile = Join-Path $here ".env.aetherion.json"
if (-not (Test-Path $envFile)) { throw "State file not found. Run 03-deploy-app.ps1 first." }
$state = Get-Content $envFile -Raw | ConvertFrom-Json

$baseUrl = "$($state.apimGatewayUrl)/aetherion"
$apiKey = $state.apimSubscriptionKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "APIM subscription key not found in state. Run 03-deploy-app.ps1 first."
}
$vus = if ($Vus -gt 0) { $Vus } elseif ($Mode -eq 'surge') { 120 } else { 25 }

# --- Separate, un-monitored resource group -----------------------------------
Write-Host "Creating load-gen resource group '$LoadGenResourceGroup'..." -ForegroundColor Cyan
az group create --name $LoadGenResourceGroup --location $Location --only-show-errors | Out-Null

# --- Storage account + file share to carry the k6 script into the container ---
$hash = [System.BitConverter]::ToString(
    ([System.Security.Cryptography.SHA1]::Create()).ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($LoadGenResourceGroup))).Replace('-', '').ToLower()
$stAccount = "aethld$($hash.Substring(0, 10))"
$share = "k6"

Write-Host "Provisioning storage for the k6 script ($stAccount)..." -ForegroundColor Cyan
az storage account create -g $LoadGenResourceGroup -n $stAccount -l $Location `
    --sku Standard_LRS --only-show-errors | Out-Null
$stKey = az storage account keys list -g $LoadGenResourceGroup -n $stAccount --query "[0].value" -o tsv
az storage share create --account-name $stAccount --account-key $stKey --name $share --only-show-errors | Out-Null
az storage file upload --account-name $stAccount --account-key $stKey --share-name $share `
    --source (Join-Path $repoRoot "load/k6-load.js") --path "k6-load.js" --only-show-errors | Out-Null

# --- (Re)create the k6 container instance ------------------------------------
Write-Host "Starting k6 on Azure Container Instance (mode=$Mode, vus=$vus)..." -ForegroundColor Cyan
az container delete -g $LoadGenResourceGroup -n aetherion-k6 --yes --only-show-errors 2>$null | Out-Null
az container create `
    -g $LoadGenResourceGroup -n aetherion-k6 `
    --image grafana/k6:latest `
    --os-type Linux --cpu 1 --memory 1.5 `
    --restart-policy Always `
    --command-line "k6 run /scripts/k6-load.js" `
    --environment-variables BASE_URL="$baseUrl" MODE="$Mode" VUS="$vus" `
    --secure-environment-variables API_KEY="$apiKey" `
    --azure-file-volume-account-name $stAccount `
    --azure-file-volume-account-key $stKey `
    --azure-file-volume-share-name $share `
    --azure-file-volume-mount-path /scripts `
    --only-show-errors | Out-Null

Write-Host "k6 load generator running in '$LoadGenResourceGroup' - hidden from the SRE Agent." -ForegroundColor Green
Write-Host "  Target : $baseUrl" -ForegroundColor Gray
Write-Host "  Mode   : $Mode ($vus VUs)" -ForegroundColor Gray
