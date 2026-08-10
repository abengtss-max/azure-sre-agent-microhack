# Aetherion AirOps - one-shot environment provisioning wrapper.
# Runs the full environment build end to end so attendees only run ONE command:
#
#   ./provision-environment.ps1
#
# Steps: provider preflight -> deploy infra -> build image -> deploy app -> validate.
# Safe to re-run: each underlying step is idempotent.
# On success it opens the tabs attendees need (Ops Center, Grafana, Azure portal
# resource group). Pass -NoLaunch to skip opening browser tabs.

param(
    [string]$ResourceGroup = "rg-aetherion-microhack",
    [string]$Location = "swedencentral",
    [string]$NamePrefix = "aetherion",
    [int]$AksNodeCount = 2,
    [string]$AksNodeVmSize = "Standard_D4s_v5",
    [ValidateSet("Consumption", "Developer")]
    [string]$ApimSkuName = "Consumption",
    [switch]$SkipProviders,
    [switch]$SkipValidate,
    [switch]$NoBanner,
    [switch]$NoLaunch,
    [switch]$UniqueSuffix
)

$ErrorActionPreference = "Stop"
$start = Get-Date
$here = $PSScriptRoot

# -UniqueSuffix: append a random 4-char suffix so multiple microhacks can share one subscription.
if ($UniqueSuffix) {
    $sfx = -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    $ResourceGroup = "$ResourceGroup-$sfx"
}

function Write-Step($n, $total, $text) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host " STEP $n/$total  $text" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}

function Show-Banner {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    $art = @(
        " █████╗  ██╗ ██████╗   ██████╗  ██████╗  ███████╗",
        "██╔══██╗ ██║ ██╔══██╗ ██╔═══██╗ ██╔══██╗ ██╔════╝",
        "███████║ ██║ ██████╔╝ ██║   ██║ ██████╔╝ ███████╗",
        "██╔══██║ ██║ ██╔══██╗ ██║   ██║ ██╔═══╝  ╚════██║",
        "██║  ██║ ██║ ██║  ██║ ╚██████╔╝ ██║      ███████║",
        "╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝      ╚══════╝"
    )
    Write-Host ""
    foreach ($line in $art) { Write-Host "   $line" -ForegroundColor Cyan }
    Write-Host ""
    Write-Host "        ✈  A E T H E R I O N   A I R O P S  ✈" -ForegroundColor White
    Write-Host ""
    Write-Host "   ╔══════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "   ║  AZURE SRE AGENT MICROHACK  ·  OPERATION CLEAR SKIES      ║" -ForegroundColor DarkCyan
    Write-Host "   ║                                                          ║" -ForegroundColor DarkCyan
    Write-Host "   ║  Mission   : Keep a Tier-0 aviation platform flying      ║" -ForegroundColor DarkCyan
    Write-Host "   ║  Stack     : AKS · APIM · PostgreSQL · Redis · Grafana   ║" -ForegroundColor DarkCyan
    Write-Host "   ║  Agent     : Reader → Contributor → Autonomous           ║" -ForegroundColor DarkCyan
    Write-Host "   ║  Status    : PROVISIONING FLIGHT DECK...                 ║" -ForegroundColor DarkCyan
    Write-Host "   ╚══════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "   🛫 Spinning up runways ......... AKS cluster"       -ForegroundColor Gray
    Write-Host "   📡 Raising control tower ....... API Management"    -ForegroundColor Gray
    Write-Host "   🗄  Fueling data systems ........ PostgreSQL + Redis" -ForegroundColor Gray
    Write-Host "   📊 Lighting the dashboards ..... Grafana + Monitor" -ForegroundColor Gray
    Write-Host "   🧠 Prepping the SRE Agent ...... Knowledge base ready" -ForegroundColor Gray
    Write-Host ""
}

# --- Preflight: make sure the tools we need are present -----------------------
if (-not $NoBanner) { Show-Banner }
Write-Host "Resource group : $ResourceGroup (auto-created)" -ForegroundColor Gray
Write-Host "Location       : $Location" -ForegroundColor Gray
Write-Host ""

foreach ($tool in @("az", "kubectl", "helm")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is not installed or not on PATH. Install it and retry."
    }
}

# Ensure the user is logged in to Azure.
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "You are not signed in to Azure. Launching 'az login'..." -ForegroundColor Yellow
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Host "Subscription   : $($account.name) ($($account.id))" -ForegroundColor Gray

$totalSteps = 6
if (-not $SkipProviders) { $totalSteps++ }

$step = 0

# --- Step 1: providers --------------------------------------------------------
if (-not $SkipProviders) {
    $step++
    Write-Step $step $totalSteps "Registering resource providers"
    & (Join-Path $here "00-check-providers.ps1") -SubscriptionId $account.id
    if ($LASTEXITCODE -ne 0) { throw "Provider registration failed." }
}

# --- Step 2: infrastructure ---------------------------------------------------
$step++
Write-Step $step $totalSteps "Deploying infrastructure (a few minutes)"
& (Join-Path $here "01-deploy-infra.ps1") `
    -ResourceGroup $ResourceGroup `
    -Location $Location `
    -NamePrefix $NamePrefix `
    -AksNodeCount $AksNodeCount `
    -AksNodeVmSize $AksNodeVmSize `
    -ApimSkuName $ApimSkuName
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed." }

# --- Step 3: build & push image ----------------------------------------------
$step++
Write-Step $step $totalSteps "Building and pushing the container image"
& (Join-Path $here "02-build-push-images.ps1")
if ($LASTEXITCODE -ne 0) { throw "Image build/push failed." }

# --- Step 4: deploy app + wire APIM + start load ------------------------------
$step++
Write-Step $step $totalSteps "Deploying the application and starting load"
& (Join-Path $here "03-deploy-app.ps1")
if ($LASTEXITCODE -ne 0) { throw "Application deployment failed." }

# --- Step 5: enable HTTPS on the domain (cert-manager + Let's Encrypt) --------
$step++
Write-Step $step $totalSteps "Enabling HTTPS on the gateway domain"
& (Join-Path $here "03b-setup-https.ps1")
if ($LASTEXITCODE -ne 0) { throw "HTTPS setup failed." }

# --- Step 6: pin the Grafana overview dashboard (home) ------------------------
$step++
Write-Step $step $totalSteps "Pinning the Grafana overview dashboard"
& (Join-Path $here "03c-setup-grafana.ps1")

# --- Step 7: validate ---------------------------------------------------------
if (-not $SkipValidate) {
    $step++
    Write-Step $step $totalSteps "Validating the environment"
    & (Join-Path $here "04-validate.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Validation reported issues. Inspect with: kubectl get pods -n aetherion" -ForegroundColor Yellow
    }
}

# --- Summary ------------------------------------------------------------------
$elapsed = (Get-Date) - $start
$envFile = Join-Path $here ".env.aetherion.json"
Write-Host ""
Write-Host "   ██████╗ ███████╗ █████╗ ██████╗ ██╗   ██╗" -ForegroundColor Green
Write-Host "   ██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝" -ForegroundColor Green
Write-Host "   ██████╔╝█████╗  ███████║██║  ██║ ╚████╔╝ " -ForegroundColor Green
Write-Host "   ██╔══██╗██╔══╝  ██╔══██║██║  ██║  ╚██╔╝  " -ForegroundColor Green
Write-Host "   ██║  ██║███████╗██║  ██║██████╔╝   ██║   " -ForegroundColor Green
Write-Host "   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝   " -ForegroundColor Green
Write-Host ""
Write-Host "   🛬 AETHERION AIROPS IS AIRBORNE  ·  cleared for the MicroHack" -ForegroundColor Green
Write-Host "   ⏱  Total provisioning time: $([int]$elapsed.TotalMinutes) min" -ForegroundColor Green
Write-Host ""
if (Test-Path $envFile) {
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    $opsCenter = if ($state.httpsUrl) { $state.httpsUrl } else { "http://$($state.gatewayIp)/" }
    Write-Host "  Ops Center : $opsCenter" -ForegroundColor Gray
    Write-Host "  API (APIM) : $($state.apimGatewayUrl)/aetherion/api/status" -ForegroundColor Gray
    Write-Host "  Grafana    : $($state.grafanaEndpoint)" -ForegroundColor Gray
    Write-Host "  Resource group: $($state.resourceGroup)" -ForegroundColor Gray
}

# --- Open the tabs the attendee needs to be successful ------------------------
if (-not $NoLaunch -and (Test-Path $envFile)) {
    $opsUrl = if ($state.httpsUrl) { $state.httpsUrl } else { "http://$($state.gatewayIp)/" }
    $subId  = az account show --query id -o tsv 2>$null

    $tabs = [ordered]@{}
    if ($opsUrl)                 { $tabs["Ops Center dashboard"] = $opsUrl }
    if ($state.grafanaEndpoint)  { $tabs["Grafana"]              = $state.grafanaEndpoint }
    if ($subId -and $state.resourceGroup) {
        $tabs["Azure portal (resource group + SRE Agent)"] =
            "https://portal.azure.com/#@/resource/subscriptions/$subId/resourceGroups/$($state.resourceGroup)/overview"
    }

    if ($tabs.Count -gt 0) {
        Write-Host ""
        Write-Host "Opening your MicroHack tabs..." -ForegroundColor Cyan
        foreach ($name in $tabs.Keys) {
            Write-Host "  → $name" -ForegroundColor Gray
            try { Start-Process $tabs[$name] | Out-Null } catch { Write-Host "    (could not open automatically: $($tabs[$name]))" -ForegroundColor DarkYellow }
            Start-Sleep -Milliseconds 500
        }
        Write-Host "  (Skip this next time with -NoLaunch.)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "When you are done, tear everything down with:" -ForegroundColor Yellow
Write-Host "  ./99-teardown.ps1" -ForegroundColor Yellow
