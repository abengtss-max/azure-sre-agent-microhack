#Requires -Version 7.0
# Aetherion AirOps - build and push the container image using ACR Tasks
# No local Docker required: 'az acr build' builds in Azure.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"

if (-not (Test-Path $envFile)) {
    throw "State file not found. Run 01-deploy-infra.ps1 first."
}
$state = Get-Content $envFile -Raw | ConvertFrom-Json

$image = "aetherion-airops:latest"
Write-Host "Building $image in ACR $($state.acrName)..." -ForegroundColor Cyan

az acr build `
    --registry $state.acrName `
    --image $image `
    --file (Join-Path $repoRoot "app/Dockerfile") `
    (Join-Path $repoRoot "app")

if ($LASTEXITCODE -ne 0) {
    throw "Image build failed."
}
Write-Host "Image pushed: $($state.acrLoginServer)/$image" -ForegroundColor Green
