# =============================================================================
# Aetherion AirOps - Challenge orchestration library (shared)
# -----------------------------------------------------------------------------
# Dot-sourced by start-challenge.ps1 and check-challenge.ps1.
#
# Responsibilities:
#   * Load environment state (scripts/.env.aetherion.json)
#   * Inject the fault(s) for a challenge WITHOUT revealing the root cause
#   * Grade the REAL remediation against live cluster / APIM state
#   * Track linear progress + unlock in a Kubernetes ConfigMap
#
# Design principles:
#   * The SRE Agent is never faked. We only inject faults and grade fixes.
#   * Fault injection lives here / in inject-failure.ps1 - never on the
#     customer-facing Ops Center dashboard.
#   * A challenge passes only when the injected fault is genuinely cleared
#     AND the affected service is healthy again (waiting it out never works,
#     because these faults persist until the env var / policy is reverted).
# =============================================================================

$ErrorActionPreference = 'Stop'

$script:NS       = 'aetherion'
$script:EnvFile  = Join-Path $PSScriptRoot '.env.aetherion.json'
$script:InjectPs = Join-Path $PSScriptRoot 'inject-failure.ps1'

# ---------------------------------------------------------------------------
# State + infrastructure helpers
# ---------------------------------------------------------------------------
function Get-AetherionState {
    if (-not (Test-Path $script:EnvFile)) {
        throw "State file not found: $script:EnvFile. Provision the environment first."
    }
    return Get-Content $script:EnvFile -Raw | ConvertFrom-Json
}

function Get-AetherionGatewayIp {
    if (Test-Path $script:EnvFile) {
        $st = Get-AetherionState
        if (-not [string]::IsNullOrWhiteSpace($st.gatewayIp)) { return $st.gatewayIp }
    }

    $gatewayIp = $null
    try {
        $gatewayIp = kubectl get service gateway -n $script:NS `
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    } catch { }

    if ([string]::IsNullOrWhiteSpace($gatewayIp)) {
        throw "State file not found at '$script:EnvFile', and the gateway IP could not be discovered from the current Kubernetes context. Provision the environment or select its AKS context first."
    }
    return $gatewayIp.Trim()
}

function Get-AetherionStatus {
    # Aggregated per-service health from the gateway (internal HTTP, no cert needed).
    $gatewayIp = Get-AetherionGatewayIp
    return Invoke-RestMethod -Uri "http://$gatewayIp/api/status" -TimeoutSec 15
}

function Test-ServiceHealthy([string]$Service, [int]$MaxLatencyMs = 0) {
    # The gateway reports a rolling window, so a service that has just recovered
    # still carries its bad samples for about a minute. Wait that out - but
    # require two consecutive good reads, so a single lucky window can't pass a
    # service that is still degraded.
    $deadline = (Get-Date).AddSeconds(120)
    $streak = 0
    while ($true) {
        $node = (Get-AetherionStatus).services.$Service
        $good = [bool]($node -and $node.ok -and ($MaxLatencyMs -le 0 -or [int]$node.latencyMs -le $MaxLatencyMs))
        if ($good) {
            $streak++
            if ($streak -ge 2) { return $true }
        }
        else { $streak = 0 }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds 10
    }
}

function Get-ServiceLatencyMs([string]$Service) {
    $node = (Get-AetherionStatus).services.$Service
    if (-not $node) { return -1 }
    return [int]$node.p95Ms
}

function Get-ServiceErrorRate([string]$Service) {
    $node = (Get-AetherionStatus).services.$Service
    if (-not $node) { return -1 }
    return [double]$node.errorRatePct
}

function Get-PoolMax([string]$Service) {
    $v = kubectl get deploy $Service -n $script:NS `
        -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='PG_POOL_MAX')].value}" 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 5 }
    return [int]$v
}

function Get-ReadyReplicas([string]$Service) {
    $v = kubectl get deploy $Service -n $script:NS -o jsonpath='{.status.readyReplicas}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 0 }
    return [int]$v
}

function Get-DesiredReplicas([string]$Service) {
    $v = kubectl get deploy $Service -n $script:NS -o jsonpath='{.spec.replicas}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 0 }
    return [int]$v
}

function Get-ImageTag([string]$Service) {
    $v = kubectl get deploy $Service -n $script:NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }
    return ($v.Split(':')[-1]).Trim()
}

function Get-CpuLimitMilli([string]$Service) {    $v = kubectl get deploy $Service -n $script:NS -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 0 }
    $v = $v.Trim()
    if ($v.EndsWith('m')) { return [int]($v.TrimEnd('m')) }
    return [int]([double]$v * 1000)
}

function Get-EnvOverride([string]$Service, [string]$Name) {
    # Only literal env entries on the deployment - the ConfigMap value is the baseline.
    $v = kubectl get deploy $Service -n $script:NS `
        -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$Name')].value}" 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }
    return $v.Trim()
}

function Get-HpaMax([string]$Service) {    $v = kubectl get hpa $Service -n $script:NS -o jsonpath='{.spec.maxReplicas}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 0 }
    return [int]$v
}

# A second revision rolled out behind the same Service (challenge 6).
function Test-CanaryPresent([string]$Service) {    $v = kubectl get deploy "$Service-v2" -n $script:NS -o jsonpath='{.spec.replicas}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    return ([int]$v -gt 0)
}

function Test-ApimHealthy {
    # 200 = the gateway is routing to the real backend again.
    $st = Get-AetherionState
    try {
        $r = Invoke-WebRequest -Uri "$($st.apimGatewayUrl)/aetherion/api/status" `
            -Headers @{ 'Ocp-Apim-Subscription-Key' = $st.apimSubscriptionKey } `
            -UseBasicParsing -TimeoutSec 20
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Invoke-Fault([string]$Service, [string]$Fault) {
    & $script:InjectPs -Service $Service -Fault $Fault | Out-Null
}

function Set-Load([string]$Mode) {
    & (Join-Path $PSScriptRoot "deploy-loadgen.ps1") -Mode $Mode 2>$null | Out-Null
}

# ---------------------------------------------------------------------------
# Progress / unlock state (Kubernetes ConfigMap: aetherion-progress)
# ---------------------------------------------------------------------------
function Set-ProgressValue([string]$Key, [string]$Value) {
    # Merge-patch so writing one key never clears the others.
    $patch = @{ data = @{ $Key = $Value } } | ConvertTo-Json -Compress
    kubectl patch configmap aetherion-progress -n $script:NS --type merge -p $patch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        kubectl create configmap aetherion-progress -n $script:NS --from-literal="$Key=$Value" 2>$null | Out-Null
    }
}

function Get-ProgressValue([string]$Key) {
    $v = kubectl get configmap aetherion-progress -n $script:NS -o jsonpath="{.data['$Key']}" 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

function Get-Unlocked {
    $v = Get-ProgressValue 'unlocked'
    if (-not $v) { Set-Unlocked 1; return 1 }
    return [int]$v
}

function Set-Unlocked([int]$n) {
    Set-ProgressValue 'unlocked' "$n"
}

function Set-ChallengeStartTime([int]$Number) {
    Set-ProgressValue "started-$Number" ([DateTime]::UtcNow.ToString('o'))
}

function Get-ChallengeStartTime([int]$Number) {
    $v = Get-ProgressValue "started-$Number"
    if (-not $v) { return $null }
    try { return [datetime]::Parse($v, $null, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
    catch { return $null }
}

function Confirm-SelfAttest([string]$Prompt) {
    $ans = Read-Host "$Prompt [y/N]"
    return ($ans -match '^(y|yes)$')
}

# ---------------------------------------------------------------------------
# Agent / alerting verification (real checks, not self-attestation)
# ---------------------------------------------------------------------------
function Get-AetherionSubscriptionId {
    $st = Get-AetherionState
    if ($st.logAnalyticsId -match '/subscriptions/([0-9a-fA-F-]{36})/') { return $Matches[1] }
    return (az account show --query id -o tsv 2>$null)
}

function Get-AgentResource {
    $st = Get-AetherionState
    $j = az resource list -g $st.resourceGroup --resource-type Microsoft.App/agents -o json 2>$null
    $agents = if ($j) { $j | ConvertFrom-Json } else { @() }
    # Attendees sometimes create the agent outside the lab resource group.
    if (-not $agents -or $agents.Count -eq 0) {
        $j = az resource list --resource-type Microsoft.App/agents -o json 2>$null
        $agents = if ($j) { $j | ConvertFrom-Json } else { @() }
    }
    if (-not $agents -or $agents.Count -eq 0) { return $null }
    $full = az resource show --ids $agents[0].id --api-version 2026-01-01 -o json 2>$null
    if (-not $full) { return $null }
    return ($full | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# SRE Agent data-plane API
#
# ARM exposes only a fraction of the agent's configuration. Everything the portal
# shows - connected repos, scheduled tasks, subagents, skills, response plans -
# lives behind the agent's own endpoint, which takes a token for the
# 'https://azuresre.ai' audience (an ARM-audience token is rejected).
#
# Every function here returns $null on ANY failure rather than throwing, so a
# grader can fall back to asking the attendee instead of failing them because a
# token expired or the API moved.
# ---------------------------------------------------------------------------
function Get-SreEndpoint {
    if ($script:SreEndpointCache) { return $script:SreEndpointCache }
    $a = Get-AgentResource
    if (-not $a -or -not $a.properties.agentEndpoint) { return $null }
    $script:SreEndpointCache = $a.properties.agentEndpoint.TrimEnd('/')
    return $script:SreEndpointCache
}

function Get-SreDataToken {
    if ($script:SreTokenCache -and (Get-Date) -lt $script:SreTokenExpiry) { return $script:SreTokenCache }
    $t = az account get-access-token --resource 'https://azuresre.ai' --query accessToken -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    $script:SreTokenCache = $t
    $script:SreTokenExpiry = (Get-Date).AddMinutes(40)
    return $t
}

# Unknown routes fall through to the SPA's index.html rather than returning 404,
# so an HTML body means "no such API", not "empty result".
function Invoke-SreData([string]$Path) {
    $ep = Get-SreEndpoint;    if (-not $ep) { return $null }
    $tok = Get-SreDataToken;  if (-not $tok) { return $null }
    try {
        $r = Invoke-WebRequest -Uri "$ep$Path" -Headers @{ Authorization = "Bearer $tok" } `
            -TimeoutSec 45 -UseBasicParsing -ErrorAction Stop
    }
    catch { return $null }
    if (-not $r.Content -or $r.Content -match '<!doctype html>') { return $null }
    # ConvertFrom-Json turns '[]' into $null, which would be indistinguishable from a
    # failed call. The comma stops PowerShell unrolling the empty array back to $null.
    if ($r.Content.Trim() -eq '[]') { return , @() }
    try { return ($r.Content | ConvertFrom-Json) } catch { return $null }
}

# Grade objectively when the API answers; ask the attendee when it cannot.
# $Probe returns $true, $false, or $null meaning "could not determine".
function Confirm-Verified([string]$Prompt, [scriptblock]$Probe, [string]$Evidence = '') {
    $result = $null
    try { $result = & $Probe } catch { $result = $null }
    if ($null -ne $result) {
        $mark = if ($result) { 'OK  ' } else { 'MISS' }
        $colour = if ($result) { 'Green' } else { 'Yellow' }
        $detail = if ($Evidence) { " ($Evidence)" } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f $mark, $Prompt, $detail) -ForegroundColor $colour
        return [bool]$result
    }
    return Confirm-SelfAttest $Prompt
}

# The response plan list is not exposed on the ARM resource, but connecting an
# incident platform is its hard prerequisite - no connection, no plan, no trigger.
function Test-IncidentPlatformConnected {
    $a = Get-AgentResource
    if (-not $a) { return $false }
    return ($a.properties.incidentManagementConfiguration.type -eq 'AzMonitor')
}

# Log Analytics shows up as a connector child resource, not on logConfiguration,
# which stays null even when the workspace is connected. GitHub is not exposed in
# ARM at all, so it can only be confirmed in the portal.
function Get-AgentContextGaps {
    $a = Get-AgentResource
    if (-not $a) { return @('agent') }
    $j = az rest --method get --uri "https://management.azure.com$($a.id)/connectors?api-version=2026-01-01" -o json 2>$null
    if (-not $j) { return @() }
    $connectors = ($j | ConvertFrom-Json).value
    $hasLaw = $connectors | Where-Object {
        $_.properties.dataConnectorType -eq 'LogAnalytics' -and $_.properties.provisioningState -eq 'Succeeded'
    }
    if ($hasLaw) { return @() }
    return @('logs/Log Analytics')
}

# The agent can diagnose the APIM fault in challenge 7 but not remediate it
# without this role, so catch a missing grant here rather than mid-incident.
function Test-AgentApimAccess {
    $st = Get-AetherionState
    $a  = Get-AgentResource
    if (-not $a) { return $false }
    $identityId = $a.properties.actionConfiguration.identity
    if (-not $identityId) { return $false }
    $principalId = az identity show --ids $identityId --query principalId -o tsv 2>$null
    if (-not $principalId) { return $false }
    $scope = az resource show -g $st.resourceGroup -n $st.apimName `
        --resource-type Microsoft.ApiManagement/service --query id -o tsv 2>$null
    if (-not $scope) { return $false }
    $n = az role assignment list --assignee-object-id $principalId --scope $scope `
        --query "[?roleDefinitionName=='API Management Service Contributor'] | length(@)" -o tsv 2>$null
    return ([int]$n -gt 0)
}

# Proves the alert -> response plan path actually works, rather than asking.
# Scoped to a start time so an earlier challenge's alert cannot satisfy this one.
function Test-MajorIncidentAlertFired([datetime]$Since) {
    $st   = Get-AetherionState
    $sub  = Get-AetherionSubscriptionId
    $rule = $st.incidentAlertName; if (-not $rule) { $rule = 'aetherion-major-incident' }
    # timeRange only accepts a fixed set of values, so pick the smallest that covers $Since.
    $age = ((Get-Date).ToUniversalTime() - $Since).TotalHours
    $range = if ($age -le 1) { '1h' } elseif ($age -le 8) { '8h' } elseif ($age -le 24) { '1d' } else { '7d' }
    $uri = "https://management.azure.com/subscriptions/$sub" +
           "/providers/Microsoft.AlertsManagement/alerts" +
           "?api-version=2019-05-05-preview&timeRange=$range"

    # az emits JSON as a string[]; piping that into ConvertFrom-Json corrupts fields.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "aeth-alerts-$PID.json"
    az rest --method get --uri $uri -o json 2>$null > $tmp
    if (-not (Test-Path $tmp)) { return $false }
    $raw = Get-Content $tmp -Raw
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor `
              [Globalization.DateTimeStyles]::AssumeUniversal
    foreach ($al in ($raw | ConvertFrom-Json).value) {
        $e = $al.properties.essentials
        if ($e.alertRule -notmatch [regex]::Escape($rule)) { continue }
        if ($e.severity -ne 'Sev1') { continue }
        [datetime]$started = [datetime]::MinValue
        if ([datetime]::TryParse($e.startDateTime, [Globalization.CultureInfo]::InvariantCulture,
                                 $styles, [ref]$started)) {
            if ($started -ge $Since) { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Challenge catalogue (scenario-driven, 8-challenge storyline)
#   Start = scriptblock that injects the fault / narrates the scenario
#   Check = scriptblock returning @{ Pass = [bool]; Detail = 'string' }
#
# Storyline note: the check-in degradation is ONE ongoing incident spanning two
# challenges. It is injected in challenge 2 (detect + investigate, read-only, no
# fix) and only resolved in challenge 3 - so challenge 3 does NOT re-inject the
# booking latency; it resolves it and adds the flight-board change on top.
#
# Consolidation map (from the earlier 13-challenge layout):
#   1  <- old 1 + 2   (onboard + baseline + proactive schedule)
#   2  <- old 3 + 4   (detect + read-only investigation; fault stays open)
#   3  <- old 5 + 6   (controlled recovery of check-in + flight-board change)
#   4  <- old 7       (ground the agent on runbooks)
#   5  <- old 8 + 9   (subagent + reusable skill)
#   6  <- old 11 + 10 (bounded autonomy + cost governance)
#   7  <- old 12      (major incident)
#   8  <- old 13      (leadership briefing)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Objective probes, built on the data-plane API above.
# Each returns $true / $false, or $null when it cannot tell (API unreachable,
# route moved, agent not created yet) so the caller can fall back to asking.
# ---------------------------------------------------------------------------

# Challenge 1: the fork must be attached AND finished cloning. A repo stuck in
# 'Cloning' looks connected in the portal but silently starves challenge 4.
function Test-CodeRepoReady {
    $r = Invoke-SreData '/api/v2/repos'
    if ($null -eq $r) { return $null }
    $repos = @($r.value)
    if ($repos.Count -eq 0) { return $false }
    return [bool](@($repos | Where-Object {
                $_.properties.url -match 'aetherion-airops-platform' -and
                $_.properties.cloneStatus -eq 'Ready'
            }).Count -gt 0)
}

function Get-CodeRepoDetail {
    $r = Invoke-SreData '/api/v2/repos'
    if ($null -eq $r) { return '' }
    $m = @($r.value) | Where-Object { $_.properties.url -match 'aetherion-airops-platform' } | Select-Object -First 1
    if (-not $m) { return 'no aetherion-airops-platform repo attached' }
    return "$($m.properties.cloneStatus)"
}

# Challenge 1: a recurring schedule, not a one-off run.
function Test-ScheduledTaskExists {
    $r = Invoke-SreData '/api/v1/scheduledtasks'
    if ($null -eq $r) { return $null }
    $tasks = @(if ($r.value) { $r.value } elseif ($r.tasks) { $r.tasks } else { $r })
    return [bool]($tasks.Count -gt 0)
}

# Challenge 5: the subagent exists, its tools are scoped rather than inherited,
# and - the point of the exercise - it holds no kubectl write tool.
function Get-SubagentSummary {
    $r = Invoke-SreData '/api/v1/extendedAgent/agents?page=1&limit=200'
    if ($null -eq $r) { return $null }
    $list = @(if ($r.value) { $r.value } elseif ($r.data) { $r.data } elseif ($r.agents) { $r.agents } else { $r })
    $sub = $list | Where-Object { "$($_.name)" -match 'aks' -or "$($_.displayName)" -match 'aks' } | Select-Object -First 1
    if (-not $sub) { return @{ Found = $false } }
    $blob = ($sub | ConvertTo-Json -Depth 12 -Compress)
    return @{
        Found    = $true
        Name     = "$($sub.name)"
        HasRead  = [bool]($blob -match 'RunKubectlReadCommand')
        HasWrite = [bool]($blob -match 'RunKubectlWriteCommand')
    }
}

# Challenge 5: the authored skill is registered on the agent.
function Test-SkillRegistered([string]$Match = 'crew') {
    $r = Invoke-SreData '/api/v2/agent/skills?limit=200'
    if ($null -eq $r) { return $null }
    $blob = ($r | ConvertTo-Json -Depth 12 -Compress)
    return [bool]($blob -match $Match)
}

# Challenge 6: the Sev1 response plan, read from the same store the portal reads.
# 'mergeEnabled' is the alert-reinvestigation cooldown; 'handlingAgent' empty
# means no subagent is bound, which is what the challenge asks for.
function Get-ResponsePlanSummary {
    $r = Invoke-SreData '/api/v1/incidentPlayground/filters'
    if ($null -eq $r) { return $null }
    $plans = @($r)
    if ($plans.Count -eq 0) { return @{ Count = 0 } }
    $sev1 = $plans | Where-Object { $_.isEnabled -and ($_.priorities -contains 'Sev1') } | Select-Object -First 1
    return @{
        Count        = $plans.Count
        Found        = [bool]$sev1
        Id           = if ($sev1) { "$($sev1.id)" } else { '' }
        Autonomous   = [bool]($sev1 -and $sev1.agentMode -eq 'autonomous')
        NoSubagent   = [bool]($sev1 -and [string]::IsNullOrWhiteSpace($sev1.handlingAgent))
        TitleFilters = [bool]($sev1 -and [string]::IsNullOrWhiteSpace($sev1.titleContains) -and @($sev1.titleNotContains).Count -eq 0)
        CooldownOff  = [bool]($sev1 -and -not $sev1.mergeEnabled)
    }
}

function Get-AgentRunMode {
    $a = Get-AgentResource
    if (-not $a) { return $null }
    return "$($a.properties.actionConfiguration.mode)"
}

# Challenge 8: the RCA and the pull request must exist on the attendee's fork.
# Uses the GitHub CLI because that is what the lab already assumes is installed;
# returns $null (ask instead) when gh is missing or unauthenticated.
function Get-ForkRepoSlug {
    $r = Invoke-SreData '/api/v2/repos'
    if ($null -ne $r) {
        $m = @($r.value) | Where-Object { $_.properties.url -match 'aetherion-airops-platform' } | Select-Object -First 1
        if ($m -and $m.properties.url -match 'github\.com/([^/]+/[^/.]+)') { return $Matches[1] }
    }
    return $null
}

function Invoke-GhJson([string]$Path) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $null }
    $out = gh api $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) { return $null }
    $text = ($out | Out-String).Trim()
    if ($text -eq '[]') { return , @() }
    try { return ($text | ConvertFrom-Json) } catch { return $null }
}

function Test-RcaIssueFiled {
    $slug = Get-ForkRepoSlug
    if (-not $slug) { return $null }
    $issues = Invoke-GhJson "repos/$slug/issues?state=all&per_page=100"
    if ($null -eq $issues) { return $null }
    return [bool](@($issues | Where-Object { $_.title -match '(?i)rca' -and -not $_.pull_request }).Count -gt 0)
}

function Test-PullRequestOpened {
    $slug = Get-ForkRepoSlug
    if (-not $slug) { return $null }
    $prs = Invoke-GhJson "repos/$slug/pulls?state=all&per_page=100"
    if ($null -eq $prs) { return $null }
    return [bool](@($prs).Count -gt 0)
}

$script:Challenges = [ordered]@{
    1 = @{
        Title = 'Onboard the Agent and Establish the Baseline'
        Kind  = 'baseline'
        Start = {
            Write-Host "No incident - the platform is green on purpose while you get oriented." -ForegroundColor Gray
            Write-Host "Open the Ops Center and Grafana, connect your SRE Agent to the resource group"
            Write-Host "in Review mode, capture a healthy baseline, then schedule that health check to"
            Write-Host "run every morning so drift is caught proactively."
        }
        Check = {
            $s = Get-AetherionStatus
            $allOk = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            if (-not $allOk) { return @{ Pass = $false; Detail = "platform not fully healthy (overall=$($s.overall))" } }
            $agent = [bool](Get-AgentResource)
            if (-not $agent) {
                Write-Host "  No Microsoft.App/agents resource found - create the SRE Agent before grading." -ForegroundColor Yellow
            }
            $apim = $agent -and (Test-AgentApimAccess)
            if ($agent -and -not $apim) {
                Write-Host "  The agent cannot manage API Management, so challenge 7 would be unfixable." -ForegroundColor Yellow
                Write-Host "  Run: ./scripts/grant-agent-apim-access.ps1" -ForegroundColor Yellow
            }
            $gaps = if ($agent) { Get-AgentContextGaps } else { @('agent') }
            $ctx  = ($gaps.Count -eq 0)
            if ($agent -and -not $ctx) {
                Write-Host "  Agent setup is incomplete, not connected to: $($gaps -join ', ')." -ForegroundColor Yellow
                Write-Host "  Reopen the agent's setup wizard and finish those connections." -ForegroundColor Yellow
            }
            # Review mode is what makes challenges 1-5 teachable, but challenge 6
            # deliberately switches to autonomous - so stop demanding review once the
            # attendee has legitimately got that far, or re-running this check fails.
            $conn = $agent -and (Confirm-Verified 'Is your SRE Agent scoped to the resource group and running in Review mode?' `
                {
                    $m = Get-AgentRunMode
                    if (-not $m) { $null }
                    elseif (Get-ChallengeStartTime 6) { $true }
                    else { $m -eq 'review' }
                } "run mode: $(Get-AgentRunMode)")
            $code = $agent -and (Confirm-Verified 'Does Builder -> Code Access list your aetherion-airops-platform fork as Connected and Ready?' `
                { Test-CodeRepoReady } (Get-CodeRepoDetail))
            $sched = Confirm-Verified 'Have you created a scheduled daily health check?' { Test-ScheduledTaskExists }
            $base = Confirm-SelfAttest 'Have you recorded a healthy baseline you could compare a future incident against?'
            @{ Pass = ($allOk -and $agent -and $apim -and $ctx -and $conn -and $code -and $base -and $sched); Detail = "platform healthy=$allOk, agentExists=$agent, apimAccess=$apim, logsConnected=$ctx, codeConnected=$code, agent connected=$conn, baseline=$base, schedule=$sched" }
        }
    }

    2 = @{
        Title = 'Detect and Investigate Without Touching Production'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'booking' 'cache-endpoint'
            Set-Load 'surge'
            Write-Host "INCIDENT P2 (open): passengers report online check-in has slowed to a crawl." -ForegroundColor Yellow
            Write-Host "Complaints are rising as a passenger surge builds. Root cause is unknown."
            Write-Host "Detect and characterize the symptom, then form a root-cause hypothesis from"
            Write-Host "telemetry and logs - all READ-ONLY. Do NOT fix it yet; the next challenge resolves it."
        }
        Check = {
            $done = Confirm-SelfAttest 'Have you confirmed the check-in degradation AND formed a read-only root-cause hypothesis backed by at least two evidence sources (no fix yet)?'
            # Banked so challenge 7 can show the attendee how much cheaper the same
            # failure class was the second time, instead of asking them to remember.
            $mins = $null
            if ($done) {
                $t0 = Get-ChallengeStartTime 2
                if ($t0) {
                    $mins = [int][math]::Round(([DateTime]::UtcNow - $t0).TotalMinutes)
                    Set-ProgressValue 'crew-minutes-cold' "$mins"
                    Write-Host "  Time on this incident: ${mins} min - banked for the comparison in challenge 7." -ForegroundColor Gray
                }
            }
            @{ Pass = $done; Detail = "symptom observed + read-only hypothesis formed=$done, minutes=$mins" }
        }
    }

    3 = @{
        Title = 'Controlled Recovery and Change Correlation'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'flight-ops' 'badimage'
            Write-Host "Two things at once. First, recover the open check-in incident with the least" -ForegroundColor Yellow
            Write-Host "disruptive safe action under human approval (Review / on-behalf-of)."
            Write-Host ""
            Write-Host "INCIDENT P1: moments later the live flight board goes dark for every station" -ForegroundColor Red
            Write-Host "shortly after a change rolled out. Correlate with deployment / rollout history,"
            Write-Host "then recover with a reversible rollback."
        }
        Check = {
            $okBook   = (Test-ServiceHealthy 'booking' 400)
            $latBook  = Get-ServiceLatencyMs 'booking'
            $cacheOk  = (Get-EnvOverride 'booking' 'REDIS_HOST') -eq ''
            $okFlight = (Test-ServiceHealthy 'flight-ops')
            $tagFlight = Get-ImageTag 'flight-ops'
            $pass = ($okBook -and $cacheOk -and $okFlight -and $tagFlight -eq 'latest')
            @{ Pass = $pass; Detail = "booking healthy=$okBook (p95 ${latBook}ms) cacheEndpointRestored=$cacheOk | flight-ops healthy=$okFlight image=:$tagFlight" }
        }
    }

    4 = @{
        Title = "Give the Agent Aetherion's Operational Knowledge"
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'crew-scheduling' 'slow-query'
            Set-Load 'crew-burst'
            Write-Host "INCIDENT P2: crew scheduling is timing out, and the services sharing its database" -ForegroundColor Yellow
            Write-Host "are slowing down with it. The database is busy, not broken - find which service is"
            Write-Host "causing it. The sanctioned remediation lives in Aetherion's runbooks, so ground the"
            Write-Host "agent in the knowledge base (repair the query path, never delete the database)."
        }
        Check = {
            $ok   = (Test-ServiceHealthy 'crew-scheduling' 400)
            $lat  = Get-ServiceLatencyMs 'crew-scheduling'
            $reps = Get-DesiredReplicas 'crew-scheduling'
            # Graded on the outcome, not on any one remedy: the roster rush is still
            # running, and only fixing the query path brings latency back inside the
            # 400ms budget. Replicas and pool headroom cannot, because the database
            # is the constraint.
            @{ Pass = $ok; Detail = "crew-scheduling healthy=$ok latency=${lat}ms (budget 400ms) replicas=$reps" }
        }
    }

    5 = @{
        Title = 'Engineer the Agent: Specialist Subagent and Reusable Skill'
        Kind  = 'config'
        Start = {
            Write-Host "The platform is stable - the right time to invest in tooling." -ForegroundColor Gray
            Write-Host "Nothing is broken in this challenge; there is no fault to find." -ForegroundColor Gray
            Write-Host "Create a custom subagent specialized in AKS triage for the aetherion namespace,"
            Write-Host "then encode the crew query-path recovery as a reusable skill (with guardrails)."
            Write-Host ""
            Write-Host "  Scope the subagent's TOOLS, do not leave them inherited. A subagent with all 46" -ForegroundColor Gray
            Write-Host "  tools is a persona, not a specialist, and its 'read-only' instruction is only a" -ForegroundColor Gray
            Write-Host "  request. Removing RunKubectlWriteCommand is what makes read-only true." -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Then decide who owns the skill. Built in the same challenge does not mean they" -ForegroundColor Gray
            Write-Host "  belong together: a skill belongs to whichever agent has both the remit AND the" -ForegroundColor Gray
            Write-Host "  tools to execute it." -ForegroundColor Gray
            Write-Host ""
            Write-Host "You will lean on both in the final incident."
        }
        Check = {
            $sa = Get-SubagentSummary
            $sub = Confirm-Verified 'Did you create an AKS-specialist subagent and use it for a scoped investigation?' `
            { if ($null -eq $sa) { $null } else { [bool]$sa.Found } } $(if ($sa -and $sa.Found) { "found '$($sa.Name)'" } else { '' })
            # The whole lesson: read tool present, write tool absent. A subagent that
            # merely *says* it is read-only in its instructions has not been scoped.
            $scoped = Confirm-Verified 'Did you scope its tools (not inherited) and verify RunKubectlReadCommand is present and RunKubectlWriteCommand is absent?' `
            { if ($null -eq $sa -or -not $sa.Found) { $null } else { $sa.HasRead -and -not $sa.HasWrite } } `
                $(if ($sa -and $sa.Found) { "read=$($sa.HasRead) write=$($sa.HasWrite)" } else { '' })
            $skill = Confirm-Verified 'Did you author a reusable recovery skill (crew query path, guardrails intact) and confirm it loads?' `
            { Test-SkillRegistered 'crew' }
            $owner = Confirm-SelfAttest 'Did you decide which agent owns the crew recovery skill, and can you say why?'
            @{ Pass = ($sub -and $scoped -and $skill -and $owner); Detail = "AKS specialist created+used=$sub, tools scoped+verified=$scoped, reusable skill authored=$skill, skill ownership decided=$owner" }
        }
    }

    6 = @{
        Title = 'Autonomous Recovery and Cost-Aware Governance'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'baggage' 'canary'
            Write-Host "INCIDENT P3 (bounded): the baggage service is returning errors to a slice of" -ForegroundColor Yellow
            Write-Host "traffic. Blast radius is small and the remediation is well understood - the safe"
            Write-Host "place to let the agent run in AUTONOMOUS mode and fix it end-to-end without waiting"
            Write-Host "for per-action approval. Watch it detect, decide and act; you supervise the outcome."
            Write-Host ""
            Write-Host "Then govern the cost: review the agent's own AAU consumption and design a" -ForegroundColor Gray
            Write-Host "cost-aware operating model that preserves reliability and investigation quality."
            Write-Host ""
            Write-Host "Finally, productize the autonomy: wire a response plan on the agent filtered to" -ForegroundColor Gray
            Write-Host "Sev1 and bound to the pre-provisioned 'aetherion-major-incident' alert, so the next"
            Write-Host "major incident auto-triggers an investigation instead of waiting for a human."
        }
        Check = {
            $ok     = (Test-ServiceHealthy 'baggage' 400)
            $err    = Get-ServiceErrorRate 'baggage'
            $canary = Test-CanaryPresent 'baggage'
            $auto = Confirm-Verified 'Did the agent remediate baggage while running in Autonomous mode (you supervised, did not fix it by hand)?' `
            { $m = Get-AgentRunMode; if (-not $m) { $null } else { $m -eq 'autonomous' } } "run mode: $(Get-AgentRunMode)"
            # "Did you write a cost model" was answerable yes by anyone who had read the
            # task. Asking for the parts that make it reviewable is still self-attested,
            # but it cannot be satisfied without having actually looked at the figures.
            $cFig  = Confirm-SelfAttest 'Did you read Settings -> Agent Consumption and write down the two largest consumers with their real figures?'
            $cLev  = Confirm-SelfAttest 'Does your operating model name at least three concrete levers, each with a figure and a stated trade-off?'
            $cFloor = Confirm-SelfAttest 'Does it state an explicit reliability floor you will not trade away for cost?'
            $cost = ($cFig -and $cLev -and $cFloor)
            if (-not $cost) {
                Write-Host "  A cost model with no figures and no floor is an opinion. Challenge 8 asks you to" -ForegroundColor Yellow
                Write-Host "  defend this one to a director - go back to Tasks 3 and 4 before you do." -ForegroundColor Yellow
            }
            $conn = Test-IncidentPlatformConnected
            if (-not $conn) {
                Write-Host "  Azure Monitor is not connected as an incident platform, so no response plan can exist." -ForegroundColor Yellow
                Write-Host "  Incidents -> Triggers + response plans -> Connect an incident platform -> Azure Monitor." -ForegroundColor Yellow
            }
            # Read from the same store the portal reads, so a plan that looks right but
            # would never fire is caught here rather than in the middle of challenge 7.
            $plan = $false
            if ($conn) {
                Write-Host ""
                Write-Host "  Checking your Sev1 response plan. Challenge 7 is graded on the alert firing." -ForegroundColor Gray
                $rp = Get-ResponsePlanSummary
                $pOn = Confirm-Verified 'Is your plan listed with Status On and Severity Sev1 (matching the pre-provisioned aetherion-major-incident alert)?' `
                { if ($null -eq $rp) { $null } else { [bool]$rp.Found } } $(if ($rp -and $rp.Found) { "plan '$($rp.Id)'" } else { '' })
                $pTitle = Confirm-Verified 'Are both title filters (contains / does not contain) empty?' `
                { if ($null -eq $rp -or -not $rp.Found) { $null } else { $rp.TitleFilters } }
                $pSub = Confirm-Verified 'Does Subagent name read "Set up", i.e. no subagent is bound to the plan?' `
                { if ($null -eq $rp -or -not $rp.Found) { $null } else { $rp.NoSubagent } }
                $pAuto = Confirm-Verified 'Is the agent autonomy level on the plan set to Autonomous?' `
                { if ($null -eq $rp -or -not $rp.Found) { $null } else { $rp.Autonomous } }
                $pCool = Confirm-Verified 'Is alert reinvestigation cooldown disabled (it defaults to 3 hours and will silently block a re-run)?' `
                { if ($null -eq $rp -or -not $rp.Found) { $null } else { $rp.CooldownOff } }
                $pQuick = Confirm-Verified 'Have you deleted the default quickstart plan that was created when you connected Azure Monitor?' `
                { if ($null -eq $rp) { $null } else { $rp.Count -le 1 } } $(if ($rp) { "$($rp.Count) plan(s) defined" } else { '' })
                $plan = ($pOn -and $pTitle -and $pSub -and $pAuto -and $pCool -and $pQuick)
                if (-not $plan) {
                    Write-Host ""
                    Write-Host "  Fix the plan now. Every 'no' above is a way for the Sev1 alert to fire and" -ForegroundColor Yellow
                    Write-Host "  your plan to ignore it, which you would not discover until Challenge 7 is" -ForegroundColor Yellow
                    Write-Host "  already open and the board is red." -ForegroundColor Yellow
                }
            }
            @{ Pass = ($ok -and $err -eq 0 -and (-not $canary) -and $auto -and $cost -and $plan); Detail = "baggage healthy=$ok errorRate=$err% canaryStillServing=$canary autonomous=$auto cost-model=$cost platformConnected=$conn responsePlan=$plan" }
        }
    }

    7 = @{
        Title = 'Final Incident: Restore Global Check-In Before Peak Departure'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'flight-ops' 'badimage'
            Invoke-Fault 'crew-scheduling' 'slow-query'
            Invoke-Fault 'booking' 'cpu-starve'
            Invoke-Fault 'apim' 'bad-backend'
            Set-Load 'major'
            Write-Host "MAJOR INCIDENT: multiple services fail at once during a passenger surge, minutes" -ForegroundColor Red
            Write-Host "before peak departures. The flight board is dark, crew and check-in are degraded,"
            Write-Host "and the API front door is failing legitimate traffic. Triage by impact and recover."
            Write-Host ""
            Write-Host "  YOU ARE NOT FIRST ON SCENE. Your Sev1 plan from Challenge 6 is armed at" -ForegroundColor Yellow
            Write-Host "  AUTONOMOUS, so within a couple of minutes 'aetherion-major-incident' fires," -ForegroundColor Yellow
            Write-Host "  auto-triggers the agent, and it starts changing things without asking you." -ForegroundColor Yellow
            Write-Host "  Find the thread it opened by itself and audit what it did before you touch" -ForegroundColor Yellow
            Write-Host "  anything. It will act on some tiers and deliberately hold on others." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Incident timeline (as customers experienced it):" -ForegroundColor Gray
            Write-Host "    18:07  A change rolls out to flight-ops"                 -ForegroundColor Gray
            Write-Host "    18:12  Check-in / booking latency begins to climb"       -ForegroundColor Gray
            Write-Host "    18:14  Crew scheduling starts timing out under load"      -ForegroundColor Gray
            Write-Host "    18:17  The live flight board goes dark for all stations"  -ForegroundColor Gray
            Write-Host "    18:21  The API front door starts failing partner traffic" -ForegroundColor Gray
            Write-Host "    18:23  'aetherion-major-incident' fires at Sev1 and auto-triggers the agent" -ForegroundColor Gray
            Write-Host "    18:25  Major incident declared - you are incident commander" -ForegroundColor Gray
            Write-Host "    18:26  The agent is already acting on its own, unattended" -ForegroundColor Gray
        }
        Check = {
            $tagFlight = Get-ImageTag 'flight-ops'
            $okCrew    = Test-ServiceHealthy 'crew-scheduling' 800
            $latCrew   = Get-ServiceLatencyMs 'crew-scheduling'
            $cpuBook   = Get-CpuLimitMilli 'booking'
            $apimOk    = Test-ApimHealthy
            $since     = Get-ChallengeStartTime 7
            if (-not $since) { $since = [DateTime]::UtcNow.AddHours(-4) }
            $fired     = Test-MajorIncidentAlertFired $since
            $s         = Get-AetherionStatus
            $allOk     = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            if (-not $fired) {
                Write-Host "  No Sev1 'major incident' alert fired since this challenge started - the auto-trigger path did not exercise." -ForegroundColor Yellow
                Write-Host "  Check the Sev1 response plan from challenge 6, then re-run start-challenge 7." -ForegroundColor Yellow
            }
            $pass = ($allOk -and $apimOk -and $tagFlight -eq 'latest' -and $okCrew -and $cpuBook -ge 500 -and $fired)
            if ($pass -and $s.overall -ne 'operational') {
                # Expected: this challenge runs an 80-VU 'major' surge, and crew is graded
                # against an 800 ms incident ceiling while the board uses a 400 ms
                # steady-state budget. Say so, or 'PASS ... overall=degraded' reads as a bug.
                Write-Host "  Board still reads '$($s.overall)': every service is serving, but the peak-departure" -ForegroundColor Gray
                Write-Host "  surge is still running and crew is above the 400ms steady-state budget (graded here" -ForegroundColor Gray
                Write-Host "  against the 800ms incident ceiling). Challenge 8 drops the load back to normal." -ForegroundColor Gray
            }
            if ($pass) {
                $cold = Get-ProgressValue 'crew-minutes-cold'
                $t0 = Get-ChallengeStartTime 7
                if ($cold -and $t0) {
                    $warm = [int][math]::Round(([DateTime]::UtcNow - $t0).TotalMinutes)
                    Write-Host ""
                    Write-Host "  Same failure class, second time round: ${cold} min in challenge 2, ${warm} min here." -ForegroundColor Cyan
                    Write-Host "  That gap is what the runbooks, the skill and the agent's memory bought you." -ForegroundColor Cyan
                    Write-Host "  Take the number to challenge 8 - it is the one figure leadership will remember." -ForegroundColor Cyan
                }
            }
            @{ Pass = $pass; Detail = "overall=$($s.overall) apimOk=$apimOk flight=:$tagFlight crew=${latCrew}ms bookingCpu=${cpuBook}m alertFired=$fired" }
        }
    }

    8 = @{
        Title = 'Boarding Resumes: Brief Airline Leadership'
        Kind  = 'config'
        Start = {
            # Peak departure is over: drop the load generator back to steady state so
            # the board actually reads green while leadership is being briefed.
            # Without this the challenge-7 'major' surge (80 VUs) keeps running and
            # the Ops Center stays amber, contradicting "boarding has resumed".
            Set-Load 'normal'
            Write-Host "The platform is stable and boarding has resumed. Close out the major incident." -ForegroundColor Gray
            Write-Host "Nothing is broken in this challenge; there is no fault to find." -ForegroundColor Gray
            Write-Host "Produce an engineering RCA handover (with change evidence) and a leadership briefing"
            Write-Host "(impact, root cause, recovery, risk, lessons), then have the agent render the briefing as a PDF with a"
            Write-Host "timeline chart. Distinguish symptom, root cause, mitigation and corrective action."
            Write-Host ""
            Write-Host "  Then close the loop for real: add the GitHub Connector and file the RCA as an" -ForegroundColor Gray
            Write-Host "  issue, then connect the GitHub MCP server and have the agent branch, commit and" -ForegroundColor Gray
            Write-Host "  open a pull request. It has been reading that repo all day without ever being" -ForegroundColor Gray
            Write-Host "  able to change a line of it." -ForegroundColor Gray
        }
        Check = {
            $s = Get-AetherionStatus
            $allOk = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            if (-not $allOk) { return @{ Pass = $false; Detail = "platform not fully healthy yet (overall=$($s.overall)) - resolve challenge 7 first" } }
            $done = Confirm-SelfAttest 'Have you produced an executive leadership briefing AND an engineering RCA handover for the major incident?'
            $pub = Confirm-Verified 'Did the agent publish the RCA as an issue on your fork of aetherion-airops-platform?' `
            { Test-RcaIssueFiled } $(if ($slug = Get-ForkRepoSlug) { "fork: $slug" } else { '' })
            $mcp = Confirm-Verified 'Did you connect an MCP server and have the agent open a pull request on your fork through it?' `
            { Test-PullRequestOpened }
            @{ Pass = ($allOk -and $done -and $pub -and $mcp); Detail = "platform healthy=$allOk, briefing + handover produced=$done, RCA published to repo=$pub, MCP pull request opened=$mcp" }
        }
    }
}

function Get-MaxChallenge { return ($script:Challenges.Keys | Measure-Object -Maximum).Maximum }

function Get-ChallengeByNumber([int]$Number) {
    # Look up by KEY. An [ordered] dictionary treats an int indexer as a positional
    # (0-based) index, so $script:Challenges[$Number] would return the wrong entry.
    foreach ($e in $script:Challenges.GetEnumerator()) {
        if ([int]$e.Key -eq $Number) { return $e.Value }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
function Start-AetherionChallenge([int]$Number) {
    if (-not $script:Challenges.Contains($Number)) {
        throw "Unknown challenge '$Number'. Valid range: 1..$(Get-MaxChallenge)."
    }
    $ch = Get-ChallengeByNumber $Number

    Write-Host ""
    Write-Host "=== Challenge $Number : $($ch.Title) ===" -ForegroundColor Cyan
    Write-Host ""
    # The agent's identity is created with the agent, so this cannot live in Bicep.
    # Idempotent and silent when the agent does not exist yet.
    & (Join-Path $PSScriptRoot 'grant-agent-apim-access.ps1') -IfPresent
    Set-ChallengeStartTime $Number
    & $ch.Start
    Write-Host ""
    if ($ch.Kind -eq 'fault') {
        Write-Host "Investigate with the Ops Center + your SRE Agent. Do NOT look at the fault scripts." -ForegroundColor Gray
    }
    Write-Host "When you believe it is resolved, verify with:" -ForegroundColor Gray
    Write-Host "  ./scripts/check-challenge.ps1 $Number" -ForegroundColor Green
    Write-Host ""
}

function Test-AetherionChallenge([int]$Number) {
    if (-not $script:Challenges.Contains($Number)) {
        throw "Unknown challenge '$Number'. Valid range: 1..$(Get-MaxChallenge)."
    }
    $ch = Get-ChallengeByNumber $Number
    Write-Host ""
    Write-Host "=== Grading challenge $Number : $($ch.Title) ===" -ForegroundColor Cyan
    $result = & $ch.Check

    Write-Host ""
    Write-Host "  $($result.Detail)" -ForegroundColor Gray
    Write-Host ""
    if ($result.Pass) {
        Write-Host "  PASS - challenge $Number resolved." -ForegroundColor Green
        # Nothing advanced this before, so 'unlocked' sat at 1 for the whole hack.
        if ((Get-Unlocked) -lt ($Number + 1)) { Set-Unlocked ($Number + 1) }
        if (-not $script:Challenges.Contains($Number + 1)) {
            Write-Host "  That was the final challenge - you have restored Aetherion AirOps. Well flown." -ForegroundColor Green
        }
        Write-Host ""
        return $true
    }
    else {
        # Not every challenge has an incident - challenge 1 is green on purpose - so
        # point at the line above rather than asserting something is broken.
        Write-Host "  NOT YET - one or more of the checks above did not pass." -ForegroundColor Yellow
        Write-Host "  The detail line shows which one. Resolve that, then re-run this check." -ForegroundColor Gray
        Write-Host ""
        return $false
    }
}
