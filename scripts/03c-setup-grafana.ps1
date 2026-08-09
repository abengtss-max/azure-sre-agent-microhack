# Aetherion AirOps - provision the Grafana "Environment Overview" dashboard.
# Imports a ready-made dashboard wired to this environment's Azure Monitor data
# source and sets it as the Grafana HOME dashboard, so attendees land straight
# on a board that reflects their environment - no Grafana knowledge required.
#
# Non-fatal by design: a Grafana hiccup must never fail the whole provisioning.

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$envFile = Join-Path $here ".env.aetherion.json"

try {
    if (-not (Test-Path $envFile)) { throw "State file not found. Run 01-deploy-infra.ps1 first." }
    $state = Get-Content $envFile -Raw | ConvertFrom-Json
    $rg = $state.resourceGroup
    $grafanaName = $state.grafanaName
    $grafanaEndpoint = ($state.grafanaEndpoint).TrimEnd('/')
    $aksName = $state.aksName
    $appiName = $state.appInsightsName
    $pgName = $state.pgServerName
    $apimName = $state.apimName
    $lawId = $state.logAnalyticsId
    $subId = az account show --query id -o tsv
    $tenantId = az account show --query tenantId -o tsv
    if ([string]::IsNullOrWhiteSpace($subId)) { throw "Could not resolve subscription id." }

    Write-Host "Ensuring Grafana CLI extension (amg)..." -ForegroundColor Cyan
    az extension add --name amg --only-show-errors 2>$null | Out-Null
    az extension update --name amg --only-show-errors 2>$null | Out-Null

    Write-Host "Locating the Azure Monitor data source..." -ForegroundColor Cyan
    $dsUid = $null
    for ($attempt = 1; $attempt -le 5 -and [string]::IsNullOrWhiteSpace($dsUid); $attempt++) {
        $dsJson = az grafana data-source list --name $grafanaName --resource-group $rg --only-show-errors -o json 2>$null
        if ($dsJson) {
            $ds = $dsJson | ConvertFrom-Json
            $azMon = $ds | Where-Object { $_.type -eq 'grafana-azure-monitor-datasource' } | Select-Object -First 1
            if (-not $azMon) { $azMon = $ds | Where-Object { $_.name -match 'Azure Monitor' } | Select-Object -First 1 }
            if ($azMon) { $dsUid = $azMon.uid }
        }
        if ([string]::IsNullOrWhiteSpace($dsUid) -and $attempt -lt 5) { Start-Sleep -Seconds 5 }
    }
    if ([string]::IsNullOrWhiteSpace($dsUid)) {
        throw "Azure Monitor data source not found on Grafana '$grafanaName'."
    }

    Write-Host "Rendering dashboard definition..." -ForegroundColor Cyan
    $template = Get-Content (Join-Path $here "grafana/aetherion-overview.json") -Raw
    $rendered = $template.
        Replace('__DS_UID__', $dsUid).
        Replace('__SUB_ID__', $subId).
        Replace('__RG__', $rg).
        Replace('__AKS__', $aksName).
        Replace('__APPI__', $appiName).
        Replace('__PG__', $pgName).
        Replace('__APIM__', $apimName).
        Replace('__LAW_ID__', $lawId).
        Replace('__TENANT__', $tenantId)
    $tmp = Join-Path $env:TEMP "aetherion-overview.rendered.json"
    $rendered | Set-Content -Path $tmp -Encoding UTF8

    Write-Host "Importing dashboard into Grafana..." -ForegroundColor Cyan
    $created = az grafana dashboard create --name $grafanaName --resource-group $rg `
        --definition $tmp --overwrite --only-show-errors -o json 2>$null | ConvertFrom-Json
    $dashUid = if ($created -and $created.uid) { $created.uid } else { "aetherion-overview" }
    Write-Host "  Dashboard imported (uid: $dashUid)." -ForegroundColor Green

    # Make it the default HOME dashboard, so it is the first thing users see.
    Write-Host "Setting it as the Grafana home dashboard..." -ForegroundColor Cyan
    $tok = az account get-access-token --resource "ce34e7e5-485f-4d76-964f-b3d2b16d1e4f" --query accessToken -o tsv 2>$null
    if (-not [string]::IsNullOrWhiteSpace($tok)) {
        $headers = @{ Authorization = "Bearer $tok" }
        try {
            $body = @{ homeDashboardUID = $dashUid } | ConvertTo-Json
            Invoke-RestMethod -Method Put -Uri "$grafanaEndpoint/api/org/preferences" -Headers $headers `
                -Body $body -ContentType "application/json" -TimeoutSec 30 | Out-Null
            Write-Host "  Home dashboard set." -ForegroundColor Green
        }
        catch {
            Write-Host "  Home dashboard preference not applied ($($_.Exception.Message)). Dashboard is still available under Dashboards." -ForegroundColor Yellow
        }
        # Star it too (best-effort; a 500 here just means it is already starred).
        try {
            Invoke-RestMethod -Method Post -Uri "$grafanaEndpoint/api/user/stars/dashboard/uid/$dashUid" `
                -Headers $headers -TimeoutSec 30 | Out-Null
        }
        catch { }
    }
    else {
        Write-Host "  Could not obtain a Grafana token; skipped setting home dashboard." -ForegroundColor Yellow
    }

    Write-Host "Grafana dashboard ready: $grafanaEndpoint (opens on 'Aetherion AirOps - Environment Overview')." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Grafana dashboard provisioning skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "The environment is unaffected; you can import scripts/grafana/aetherion-overview.json manually if needed." -ForegroundColor Yellow
    exit 0
}
