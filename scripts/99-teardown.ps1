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

# Free the APIM name before the group goes away. APIM soft-delete survives
# resource-group deletion and would otherwise block a future redeploy into the
# same group with 'ServiceAlreadyExistsInSoftDeletedState'. Best-effort; the
# deploy script also self-heals by purging on the next run.
try {
    $apims = az apim list -g $ResourceGroup --query "[].{name:name,location:location}" -o json 2>$null | ConvertFrom-Json
    foreach ($a in $apims) {
        Write-Host "  Deleting + purging APIM '$($a.name)'..." -ForegroundColor Gray
        az apim delete -g $ResourceGroup -n $a.name --yes --only-show-errors 2>$null | Out-Null
        $loc = ($a.location -replace '\s', '').ToLower()
        az apim deletedservice purge --service-name $a.name --location $loc --only-show-errors 2>$null | Out-Null
    }
} catch { }

az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Deletion started (running in background). Resources will be gone shortly." -ForegroundColor Green

# The k6 load generator lives in a separate resource group; tear it down too.
$loadGenRg = "$ResourceGroup-loadgen"
if ((az group exists --name $loadGenRg 2>$null) -eq 'true') {
    Write-Host "Deleting load-gen resource group '$loadGenRg'..." -ForegroundColor Cyan
    az group delete --name $loadGenRg --yes --no-wait
}

if (Test-Path $envFile) {
    Remove-Item $envFile -Force
    Write-Host "Removed local state file." -ForegroundColor Gray
}
