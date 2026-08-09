# Aetherion AirOps - tear down the entire environment.
# Deletes the resource group (all resources) so nothing keeps billing after the event.

param(
    [string]$ResourceGroup = "",
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    if (Test-Path $envFile) {
        $state = Get-Content $envFile -Raw | ConvertFrom-Json
        $ResourceGroup = $state.resourceGroup
    }
}
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw "Specify -ResourceGroup or run after 01-deploy-infra.ps1 created the state file."
}

Write-Host "This will DELETE resource group '$ResourceGroup' and everything in it." -ForegroundColor Red
if (-not $Yes) {
    $confirm = Read-Host "Type the resource group name to confirm"
    if ($confirm -ne $ResourceGroup) { Write-Host "Aborted." -ForegroundColor Yellow; exit 1 }
}

Write-Host "Deleting resource group '$ResourceGroup'..." -ForegroundColor Cyan
az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Deletion started (running in background). Resources will be gone shortly." -ForegroundColor Green

if (Test-Path $envFile) {
    Remove-Item $envFile -Force
    Write-Host "Removed local state file." -ForegroundColor Gray
}
