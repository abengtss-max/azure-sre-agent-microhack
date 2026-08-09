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
    "Microsoft.Cache",
    "Microsoft.ApiManagement",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.Insights",
    "Microsoft.Dashboard",
    "Microsoft.Authorization",
    "Microsoft.Network",
    "Microsoft.Compute",
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

if ($toRegister.Count -eq 0) {
    Write-Host "All providers already registered." -ForegroundColor Green
    exit 0
}

Write-Host "Waiting for $($toRegister.Count) provider(s) to finish registering..." -ForegroundColor Cyan
foreach ($p in $toRegister) {
    do {
        Start-Sleep -Seconds 10
        $state = az provider show --namespace $p --query registrationState -o tsv 2>$null
        Write-Host "  [$p] = $state"
    } while ($state -ne "Registered")
}

Write-Host "All required providers are registered." -ForegroundColor Green
