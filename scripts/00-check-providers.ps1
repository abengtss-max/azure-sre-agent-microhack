#Requires -Version 7.0
# Aetherion AirOps - resource provider preflight
# Registers every Azure resource provider the environment needs BEFORE deployment
# so the Bicep deployment never fails halfway on an unregistered provider.

param(
    [string]$SubscriptionId = ""
)

$ErrorActionPreference = "Stop"

if ($SubscriptionId -ne "") {
    Write-Host "Setting subscription to $SubscriptionId" -ForegroundColor Cyan
    az account set --subscription $SubscriptionId
}

$providers = @(
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.ApiManagement",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.Insights",
    "Microsoft.Monitor",
    "Microsoft.AlertsManagement",
    "Microsoft.Dashboard",
    "Microsoft.Authorization",
    "Microsoft.Network",
    "Microsoft.Compute",
    "Microsoft.ContainerInstance",
    "Microsoft.Storage"
)

Write-Host "Checking $($providers.Count) resource providers..." -ForegroundColor Cyan
$toRegister = @()

foreach ($p in $providers) {
    $state = az provider show --namespace $p --query registrationState -o tsv 2>$null
    if ($state -ne "Registered") {
        Write-Host "  [$p] = $state -> registering" -ForegroundColor Yellow
        az provider register --namespace $p | Out-Null
        $toRegister += $p
    } else {
        Write-Host "  [$p] = Registered" -ForegroundColor Green
    }
}

if ($toRegister.Count -gt 0) {
    Write-Host "Waiting for $($toRegister.Count) provider(s) to finish registering..." -ForegroundColor Cyan
    foreach ($p in $toRegister) {
        do {
            Start-Sleep -Seconds 10
            $state = az provider show --namespace $p --query registrationState -o tsv 2>$null
            Write-Host "  [$p] = $state"
        } while ($state -ne "Registered")
    }
}

# --- Required subscription FEATURES (beyond provider registration) ------------
# Governed / "subscription-vending" tenants can intercept public-IP creation so
# that AKS's load-balancer public IP requires this feature. Without it the AKS
# node pool never comes up (control plane stays 'Creating' with no VMSS) - in
# every region, and via the portal too.
Write-Host "Checking required subscription features..." -ForegroundColor Cyan
$features = @(
    @{ ns = "Microsoft.Network"; name = "AllowBringYourOwnPublicIpAddress" }
)
$featureChanged = @()
foreach ($f in $features) {
    $fstate = az feature show --namespace $f.ns --name $f.name --query properties.state -o tsv 2>$null
    if ($fstate -ne "Registered") {
        Write-Host "  [$($f.ns)/$($f.name)] = $fstate -> registering" -ForegroundColor Yellow
        az feature register --namespace $f.ns --name $f.name | Out-Null
        $tries = 0
        do {
            Start-Sleep -Seconds 10
            $fstate = az feature show --namespace $f.ns --name $f.name --query properties.state -o tsv 2>$null
            $tries++
        } while ($fstate -ne "Registered" -and $tries -lt 30)
        Write-Host "  [$($f.ns)/$($f.name)] = $fstate" -ForegroundColor $(if ($fstate -eq 'Registered') { 'Green' } else { 'Yellow' })
        $featureChanged += $f.ns
    } else {
        Write-Host "  [$($f.ns)/$($f.name)] = Registered" -ForegroundColor Green
    }
}
# Re-register any provider whose feature just changed so it takes effect.
foreach ($ns in ($featureChanged | Select-Object -Unique)) {
    Write-Host "  Re-registering $ns to propagate new feature(s)..." -ForegroundColor Cyan
    az provider register --namespace $ns | Out-Null
}

Write-Host "All required providers and features are registered." -ForegroundColor Green
