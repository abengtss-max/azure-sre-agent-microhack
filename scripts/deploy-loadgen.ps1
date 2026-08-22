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
    [ValidateSet("normal", "surge", "crew-burst", "major")]
    [string]$Mode = "normal",
    [int]$Vus = 0,
    # How long to wait for the container to actually start before handing control back.
    [int]$TimeoutSeconds = 120
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
# Aetherion's own stations and mobile backend reach the platform directly, so a
# fault at the partner front door does not take the workload idle.
$directUrl = if ([string]::IsNullOrWhiteSpace($state.gatewayIp)) { '' } else { "http://$($state.gatewayIp)" }
$vus = if ($Vus -gt 0) { $Vus } elseif ($Mode -eq 'surge') { 200 } elseif ($Mode -eq 'crew-burst') { 150 } elseif ($Mode -eq 'major') { 80 } else { 25 }
# Aetherion's own stations and mobile backend carry most of a departure wave;
# partner API traffic is the smaller share. During a major incident that split
# matters, because a fault at the partner front door must not take the platform
# idle and hide everything behind it.
$internalVus = if ($Mode -eq 'major') { 60 } else { 12 }
$crewVus = if ($Mode -eq 'major') { 120 } else { 0 }
$checkInVus = if ($Mode -eq 'major') { 120 } else { 0 }

# --- Separate, un-monitored resource group -----------------------------------
if ((az group exists --name $LoadGenResourceGroup) -eq 'true') {
    Write-Host "Reusing load-gen resource group '$LoadGenResourceGroup'." -ForegroundColor Cyan
} else {
    Write-Host "Creating load-gen resource group '$LoadGenResourceGroup'..." -ForegroundColor Cyan
}
az group create --name $LoadGenResourceGroup --location $Location --only-show-errors | Out-Null

# --- Carry the k6 script into the container via an ACI secret volume ---------
# No storage account (governed subs disable storage shared-key, which ACI Azure
# Files needs) and no registry auth (grafana/k6 is public). The script is gzipped
# before base64 because the whole thing travels on the command line, which has a
# hard length limit on Windows.
$scriptBytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot "load/k6-load.js"))
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$gz.Write($scriptBytes, 0, $scriptBytes.Length)
$gz.Dispose()
$scriptB64 = [Convert]::ToBase64String($ms.ToArray())
$ms.Dispose()

Write-Host "Redeploying k6 load generator on Azure Container Instance (mode=$Mode, vus=$vus)..." -ForegroundColor Cyan
az container delete -g $LoadGenResourceGroup -n aetherion-k6 --yes --only-show-errors 2>$null | Out-Null
az container create `
    -g $LoadGenResourceGroup -n aetherion-k6 `
    --image grafana/k6:latest `
    --os-type Linux --cpu 2 --memory 2 `
    --restart-policy Always `
    --command-line "sh -c 'base64 -d /scripts/k6-load.js.gz > /tmp/k6.gz && gunzip -c /tmp/k6.gz > /tmp/k6-load.js && k6 run /tmp/k6-load.js'" `
    --environment-variables BASE_URL="$baseUrl" DIRECT_URL="$directUrl" MODE="$Mode" VUS="$vus" INTERNAL_VUS="$internalVus" CREW_VUS="$crewVus" CHECKIN_VUS="$checkInVus" `
    --secure-environment-variables API_KEY="$apiKey" `
    --secrets "k6-load.js.gz=$scriptB64" `
    --secrets-mount-path /scripts `
    --no-wait `
    --only-show-errors | Out-Null

# ACI can sit in "Waiting to run" for minutes on a slow control plane or a Docker Hub
# pull. The fault is already applied and the gateway's own poller feeds the Ops Center,
# so the incident is live without k6 - never hold the challenge open on this.
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$containerState = ''
while ((Get-Date) -lt $deadline) {
    $containerState = az container show -g $LoadGenResourceGroup -n aetherion-k6 `
        --query 'containers[0].instanceView.currentState.state' -o tsv --only-show-errors 2>$null
    if ($containerState -eq 'Running') { break }
    Start-Sleep -Seconds 5
}

if ($containerState -eq 'Running') {
    Write-Host "k6 load generator running in '$LoadGenResourceGroup' - hidden from the SRE Agent." -ForegroundColor Green
} else {
    Write-Host "k6 load generator is still starting in '$LoadGenResourceGroup' (state: $(if ($containerState) { $containerState } else { 'pending' }))." -ForegroundColor Yellow
    Write-Host "  Continuing anyway - this only adds background traffic. The incident is already live" -ForegroundColor Yellow
    Write-Host "  and visible in the Operations Center. Check later with:" -ForegroundColor Yellow
    Write-Host "    az container show -g $LoadGenResourceGroup -n aetherion-k6 --query containers[0].instanceView.currentState" -ForegroundColor Gray
}
Write-Host "  Partner  : $baseUrl" -ForegroundColor Gray
if ($directUrl) { Write-Host "  Internal : $directUrl ($internalVus mixed$(if ($crewVus -gt 0) { ", $crewVus crew sign-on, $checkInVus check-in" }))" -ForegroundColor Gray }
Write-Host "  Mode     : $Mode ($vus VUs)" -ForegroundColor Gray
