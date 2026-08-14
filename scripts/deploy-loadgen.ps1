#Requires -Version 7.0
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
    # Hack resource group - defaults to the state file's value so it follows the provisioned RG.
    [string]$ResourceGroup = "",
    # Separate resource group for the load generator (NOT monitored by the agent).
    [string]$LoadGenResourceGroup = "",
    [string]$Location = "",
    [ValidateSet("normal", "surge", "crew-burst")]
    [string]$Mode = "normal",
    [int]$Vus = 0
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
$envFile = Join-Path $here ".env.aetherion.json"
if (-not (Test-Path $envFile)) { throw "State file not found. Run 03-deploy-app.ps1 first." }
$state = Get-Content $envFile -Raw | ConvertFrom-Json

# Resolve the target from the state file when not passed explicitly, so surge/reset
# always hit the correct (suffixed) environment - never a hardcoded name.
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = $state.resourceGroup }
if ([string]::IsNullOrWhiteSpace($Location)) { $Location = if ($state.location) { $state.location } else { "swedencentral" } }
# Load-gen RG is derived from the hack RG so it's always paired but separate.
if ([string]::IsNullOrWhiteSpace($LoadGenResourceGroup)) { $LoadGenResourceGroup = "$ResourceGroup-loadgen" }

$baseUrl = "$($state.apimGatewayUrl)/aetherion"
$apiKey = $state.apimSubscriptionKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "APIM subscription key not found in state. Run 03-deploy-app.ps1 first."
}
$vus = if ($Vus -gt 0) { $Vus } elseif ($Mode -eq 'surge') { 120 } elseif ($Mode -eq 'crew-burst') { 150 } else { 25 }

# --- Separate, un-monitored resource group -----------------------------------
if ((az group exists --name $LoadGenResourceGroup) -eq 'true') {
    Write-Host "Reusing load-gen resource group '$LoadGenResourceGroup'." -ForegroundColor Cyan
} else {
    Write-Host "Creating load-gen resource group '$LoadGenResourceGroup'..." -ForegroundColor Cyan
}
az group create --name $LoadGenResourceGroup --location $Location --only-show-errors | Out-Null

# --- Carry the k6 script into the container via an ACI secret volume ---------
# No storage account (governed subs disable storage shared-key, which ACI Azure
# Files needs) and no registry auth (grafana/k6 is public). The secret value is
# the base64 of the script; ACI mounts the decoded file at /scripts/k6-load.js.
$scriptB64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $repoRoot "load/k6-load.js")))

Write-Host "Redeploying k6 load generator on Azure Container Instance (mode=$Mode, vus=$vus)..." -ForegroundColor Cyan
az container delete -g $LoadGenResourceGroup -n aetherion-k6 --yes --only-show-errors 2>$null | Out-Null
az container create `
    -g $LoadGenResourceGroup -n aetherion-k6 `
    --image grafana/k6:latest `
    --os-type Linux --cpu 1 --memory 1.5 `
    --restart-policy Always `
    --command-line "sh -c 'base64 -d /scripts/k6-load.js > /tmp/k6-load.js && k6 run /tmp/k6-load.js'" `
    --environment-variables BASE_URL="$baseUrl" MODE="$Mode" VUS="$vus" `
    --secure-environment-variables API_KEY="$apiKey" `
    --secrets "k6-load.js=$scriptB64" `
    --secrets-mount-path /scripts `
    --only-show-errors | Out-Null

Write-Host "k6 load generator running in '$LoadGenResourceGroup' - hidden from the SRE Agent." -ForegroundColor Green
Write-Host "  Target : $baseUrl" -ForegroundColor Gray
Write-Host "  Mode   : $Mode ($vus VUs)" -ForegroundColor Gray
