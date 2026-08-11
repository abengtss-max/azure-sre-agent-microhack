# Aetherion AirOps - tear down microhack environment(s).
# Each microhack is a pair: the hack resource group plus its '<rg>-loadgen' group.
# In a shared subscription there may be several (each provision creates a suffixed RG), so
# with no arguments this discovers them and lets you pick which to delete.
#
#   ./99-teardown.ps1                 # interactive: list + pick
#   ./99-teardown.ps1 -ResourceGroup rg-aetherion-microhack-a7c3   # target one
#   ./99-teardown.ps1 -All            # every Aetherion microhack in the sub
#   ./99-teardown.ps1 -ResourceGroup <rg> -Yes                     # non-interactive

param(
    [string]$ResourceGroup = "",
    [switch]$All,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot ".env.aetherion.json"

# Delete one microhack: purge its APIM (soft-delete would block a future redeploy),
# then delete the hack RG and its load-gen pair. Best-effort on APIM.
function Remove-Microhack([string]$rg) {
    Write-Host "Deleting resource group '$rg'..." -ForegroundColor Cyan
    try {
        $apims = az apim list -g $rg --query "[].{name:name,location:location}" -o json 2>$null | ConvertFrom-Json
        foreach ($a in $apims) {
            Write-Host "  Deleting + purging APIM '$($a.name)'..." -ForegroundColor Gray
            az apim delete -g $rg -n $a.name --yes --only-show-errors 2>$null | Out-Null
            $loc = ($a.location -replace '\s', '').ToLower()
            az apim deletedservice purge --service-name $a.name --location $loc --only-show-errors 2>$null | Out-Null
        }
    } catch { }
    az group delete --name $rg --yes --no-wait
    Write-Host "  Deletion started for '$rg' (background)." -ForegroundColor Green

    $lg = "$rg-loadgen"
    if ((az group exists --name $lg 2>$null) -eq 'true') {
        Write-Host "  Deleting load-gen resource group '$lg'..." -ForegroundColor Cyan
        az group delete --name $lg --yes --no-wait
    }
}

# --- Resolve which microhack(s) to delete ------------------------------------
$targets = @()

if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $targets = @($ResourceGroup)
}
else {
    Write-Host "Scanning subscription for Aetherion microhack resource groups..." -ForegroundColor Cyan
    $hackRgs = az group list --query "[?starts_with(name,'rg-aetherion-microhack') && !ends_with(name,'-loadgen')].{name:name, location:location}" -o json 2>$null | ConvertFrom-Json
    $hackRgs = @($hackRgs)

    if ($hackRgs.Count -eq 0) {
        Write-Host "No Aetherion microhack resource groups found." -ForegroundColor Yellow
        if (Test-Path $envFile) { Remove-Item $envFile -Force; Write-Host "Removed stale local state file." -ForegroundColor Gray }
        exit 0
    }

    if ($All) {
        $targets = $hackRgs | ForEach-Object { $_.name }
    }
    elseif ($hackRgs.Count -eq 1) {
        $targets = @($hackRgs[0].name)
    }
    else {
        Write-Host ""
        Write-Host "Aetherion microhacks found in this subscription:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host ("  {0,-3} {1,-34} {2,-38} {3}" -f '#', 'Microhack RG', 'Load-gen RG', 'Location') -ForegroundColor Gray
        for ($i = 0; $i -lt $hackRgs.Count; $i++) {
            $h = $hackRgs[$i]
            $lg = "$($h.name)-loadgen"
            $lgShown = if ((az group exists --name $lg 2>$null) -eq 'true') { $lg } else { "(none)" }
            Write-Host ("  {0,-3} {1,-34} {2,-38} {3}" -f ($i + 1), $h.name, $lgShown, $h.location)
        }
        Write-Host ""
        $pick = Read-Host "Which do you want to tear down?  [1-$($hackRgs.Count) / A=all / Q=quit]"
        if ($pick -match '^[Qq]') { Write-Host "Aborted." -ForegroundColor Yellow; exit 1 }
        elseif ($pick -match '^[Aa]') { $targets = $hackRgs | ForEach-Object { $_.name } }
        elseif ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $hackRgs.Count) {
            $targets = @($hackRgs[[int]$pick - 1].name)
        }
        else { Write-Host "Invalid selection. Aborted." -ForegroundColor Yellow; exit 1 }
    }
}

$targets = @($targets)
if ($targets.Count -eq 0) { Write-Host "Nothing to delete." -ForegroundColor Yellow; exit 0 }

# --- Show the exact deletion plan (hack RG + its load-gen pair) ---------------
Write-Host ""
Write-Host "Will DELETE the following (each microhack RG plus its load-gen pair):" -ForegroundColor Red
foreach ($t in $targets) {
    Write-Host "  * $t" -ForegroundColor Red
    $lg = "$t-loadgen"
    if ((az group exists --name $lg 2>$null) -eq 'true') { Write-Host "  * $lg" -ForegroundColor Red }
}
Write-Host ""

# --- Confirm ------------------------------------------------------------------
if (-not $Yes) {
    if ($targets.Count -eq 1) {
        $confirm = Read-Host "Type the microhack RG name to confirm"
        if ($confirm -ne $targets[0]) { Write-Host "Aborted." -ForegroundColor Yellow; exit 1 }
    }
    else {
        $confirm = Read-Host "Type DELETE to remove all $($targets.Count) microhacks above"
        if ($confirm -ne 'DELETE') { Write-Host "Aborted." -ForegroundColor Yellow; exit 1 }
    }
}

# --- Delete -------------------------------------------------------------------
foreach ($t in $targets) { Remove-Microhack $t }

# --- Local state cleanup: only if it points at a deleted target ---------------
if (Test-Path $envFile) {
    $stateRg = ""
    try { $stateRg = (Get-Content $envFile -Raw | ConvertFrom-Json).resourceGroup } catch { }
    if ([string]::IsNullOrWhiteSpace($stateRg) -or ($targets -contains $stateRg)) {
        Remove-Item $envFile -Force
        Write-Host "Removed local state file." -ForegroundColor Gray
    }
    else {
        Write-Host "Kept local state file (belongs to '$stateRg', which was not deleted)." -ForegroundColor Gray
    }
}

Write-Host "Teardown initiated. Resources are deleting in the background." -ForegroundColor Green
