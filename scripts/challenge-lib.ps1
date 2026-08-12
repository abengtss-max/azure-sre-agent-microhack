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

function Get-AetherionStatus {
    # Aggregated per-service health from the gateway (internal HTTP, no cert needed).
    $st = Get-AetherionState
    return Invoke-RestMethod -Uri "http://$($st.gatewayIp)/api/status" -TimeoutSec 15
}

function Test-ServiceHealthy([string]$Service) {
    $s = Get-AetherionStatus
    $node = $s.services.$Service
    return [bool]($node -and $node.ok)
}

function Get-FaultMode([string]$Service) {
    # Read the opaque service profile and translate it back to the internal fault
    # name so grading stays readable. The deployment only ever exposes the opaque
    # SVC_PROFILE value (e.g. r1), never the fault name (e.g. latency).
    $v = kubectl get deploy $Service -n $script:NS `
        -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='SVC_PROFILE')].value}" 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { return 'none' }
    $map = @{ 'standard' = 'none'; 'r1' = 'latency'; 'r2' = 'error'; 'r3' = 'crash'; 'r4' = 'memory'; 'r5' = 'db-pool' }
    $key = $v.Trim().ToLower()
    if ($map.ContainsKey($key)) { return $map[$key] }
    return $key
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

function Test-ApimHealthy {
    # 200 = routing OK / throttle cleared. 429 (throttled) throws -> false.
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
function Get-Unlocked {
    $v = kubectl get configmap aetherion-progress -n $script:NS -o jsonpath='{.data.unlocked}' 2>$null
    if ([string]::IsNullOrWhiteSpace($v)) { Set-Unlocked 1; return 1 }
    return [int]$v
}

function Set-Unlocked([int]$n) {
    kubectl create configmap aetherion-progress -n $script:NS `
        --from-literal=unlocked=$n --dry-run=client -o yaml 2>$null | kubectl apply -f - 2>$null | Out-Null
}

function Confirm-SelfAttest([string]$Prompt) {
    $ans = Read-Host "$Prompt [y/N]"
    return ($ans -match '^(y|yes)$')
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
$script:Challenges = [ordered]@{
    1 = @{
        Title = 'Onboard the Agent and Establish the Baseline'
        Kind  = 'baseline'
        Start = {
            Write-Host "No incident - the platform is green on purpose while you get oriented." -ForegroundColor Gray
            Write-Host "Open the Ops Center and Grafana, connect your SRE Agent to the resource group"
            Write-Host "in Reader (read-only) mode, capture a healthy baseline, then schedule that"
            Write-Host "health check to run every morning so drift is caught proactively."
        }
        Check = {
            $s = Get-AetherionStatus
            $allOk = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            if (-not $allOk) { return @{ Pass = $false; Detail = "platform not fully healthy (overall=$($s.overall))" } }
            $conn = Confirm-SelfAttest 'Is your SRE Agent connected to the resource group in Reader mode?'
            $base = Confirm-SelfAttest 'Have you recorded a healthy baseline AND created a scheduled daily health check?'
            @{ Pass = ($allOk -and $conn -and $base); Detail = "platform healthy=$allOk, agent connected=$conn, baseline+schedule=$base" }
        }
    }

    2 = @{
        Title = 'Detect and Investigate Without Touching Production'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'booking' 'latency'
            Set-Load 'surge'
            Write-Host "INCIDENT P2 (open): passengers report online check-in and booking are slow." -ForegroundColor Yellow
            Write-Host "Complaints are rising as a passenger surge builds. Root cause is unknown."
            Write-Host "Detect and characterize the symptom, then form a root-cause hypothesis from"
            Write-Host "telemetry and logs - all READ-ONLY. Do NOT fix it yet; the next challenge resolves it."
        }
        Check = {
            $done = Confirm-SelfAttest 'Have you confirmed the check-in degradation AND formed a read-only root-cause hypothesis backed by at least two evidence sources (no fix yet)?'
            @{ Pass = $done; Detail = "symptom observed + read-only hypothesis formed=$done" }
        }
    }

    3 = @{
        Title = 'Controlled Recovery and Change Correlation'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'flight-ops' 'crash'
            Write-Host "Two things at once. First, recover the open check-in incident with the least" -ForegroundColor Yellow
            Write-Host "disruptive safe action under human approval (Review / on-behalf-of)."
            Write-Host ""
            Write-Host "INCIDENT P1: moments later the live flight board goes dark for every station" -ForegroundColor Red
            Write-Host "shortly after a change rolled out. Correlate with deployment / rollout history"
            Write-Host "(and the GitHub change record), then recover with a reversible rollback."
        }
        Check = {
            $fmBook   = Get-FaultMode 'booking'
            $okBook   = (Test-ServiceHealthy 'booking')
            $fmFlight = Get-FaultMode 'flight-ops'
            $okFlight = (Test-ServiceHealthy 'flight-ops')
            $pass = ($okBook -and $fmBook -ne 'latency' -and $okFlight -and $fmFlight -ne 'crash')
            @{ Pass = $pass; Detail = "booking healthy=$okBook faultMode=$fmBook | flight-ops healthy=$okFlight faultMode=$fmFlight" }
        }
    }

    4 = @{
        Title = "Give the Agent Aetherion's Operational Knowledge"
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'crew-scheduling' 'db-pool'
            Write-Host "INCIDENT P2: crew scheduling requests hang then error; only this service is affected." -ForegroundColor Yellow
            Write-Host "The sanctioned remediation lives in Aetherion's runbooks - ground the agent in the"
            Write-Host "knowledge base so it recommends the approved fix (scale, never delete the database)."
        }
        Check = {
            $fm   = Get-FaultMode 'crew-scheduling'
            $ok   = (Test-ServiceHealthy 'crew-scheduling')
            $pool = Get-PoolMax 'crew-scheduling'
            $note = if ($pool -gt 5) { " (pool raised to $pool)" } else { '' }
            @{ Pass = ($ok -and $fm -ne 'db-pool'); Detail = "crew-scheduling healthy=$ok faultMode=$fm$note" }
        }
    }

    5 = @{
        Title = 'Engineer the Agent: Specialist Subagent and Reusable Skill'
        Kind  = 'config'
        Start = {
            Write-Host "The platform is stable - the right time to invest in tooling." -ForegroundColor Gray
            Write-Host "Create a custom subagent specialized in AKS triage for the aetherion namespace,"
            Write-Host "then encode the crew pool-relief recovery as a reusable skill (with guardrails)."
            Write-Host "You will lean on both in the final incident."
        }
        Check = {
            $sub   = Confirm-SelfAttest 'Did you create an AKS-specialist subagent and use it for a scoped investigation?'
            $skill = Confirm-SelfAttest 'Did you author a reusable recovery skill (crew pool-relief, guardrails intact) and confirm it loads?'
            @{ Pass = ($sub -and $skill); Detail = "AKS specialist created+used=$sub, reusable skill authored=$skill" }
        }
    }

    6 = @{
        Title = 'Autonomous Recovery and Cost-Aware Governance'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'baggage' 'error'
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
            $fm   = Get-FaultMode 'baggage'
            $ok   = (Test-ServiceHealthy 'baggage')
            $auto = Confirm-SelfAttest 'Did the agent remediate baggage while running in Autonomous mode (you supervised, did not fix it by hand)?'
            $cost = Confirm-SelfAttest 'Have you reviewed agent consumption and produced a cost-aware operating model (not just the cheapest option)?'
            $plan = Confirm-SelfAttest 'Have you created a Sev1-filtered major-incident response plan on the agent (bound to the aetherion-major-incident alert) so the next major incident auto-triggers an investigation?'
            @{ Pass = ($ok -and $fm -ne 'error' -and $auto -and $cost -and $plan); Detail = "baggage healthy=$ok faultMode=$fm autonomous=$auto cost-model=$cost responsePlan=$plan" }
        }
    }

    7 = @{
        Title = 'Final Incident: Restore Global Check-In Before Peak Departure'
        Kind  = 'fault'
        Start = {
            Invoke-Fault 'flight-ops' 'crash'
            Invoke-Fault 'crew-scheduling' 'db-pool'
            Invoke-Fault 'booking' 'latency'
            Invoke-Fault 'apim' 'throttle'
            Set-Load 'surge'
            Write-Host "MAJOR INCIDENT: multiple services fail at once during a passenger surge, minutes" -ForegroundColor Red
            Write-Host "before peak departures. The flight board is dark, crew and check-in are degraded,"
            Write-Host "and the API front door is rejecting legitimate traffic. Triage by impact and recover."
            Write-Host ""
            Write-Host "  Your Sev1 response plan from Challenge 6 should already be armed - within a couple" -ForegroundColor Gray
            Write-Host "  of minutes the 'aetherion-major-incident' alert fires and auto-triggers the agent." -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Incident timeline (as customers experienced it):" -ForegroundColor Gray
            Write-Host "    18:07  A change rolls out to flight-ops"                 -ForegroundColor Gray
            Write-Host "    18:12  Check-in / booking latency begins to climb"       -ForegroundColor Gray
            Write-Host "    18:14  Crew scheduling starts timing out under load"      -ForegroundColor Gray
            Write-Host "    18:17  The live flight board goes dark for all stations"  -ForegroundColor Gray
            Write-Host "    18:21  The API front door begins throttling partners"      -ForegroundColor Gray
            Write-Host "    18:25  Major incident declared - you are incident commander" -ForegroundColor Gray
        }
        Check = {
            $fFlight = Get-FaultMode 'flight-ops'
            $fCrew   = Get-FaultMode 'crew-scheduling'
            $fBook   = Get-FaultMode 'booking'
            $apimOk  = Test-ApimHealthy
            $s       = Get-AetherionStatus
            $allOk   = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            $pass = ($allOk -and $apimOk -and $fFlight -ne 'crash' -and $fCrew -ne 'db-pool' -and $fBook -ne 'latency')
            @{ Pass = $pass; Detail = "overall=$($s.overall) apimOk=$apimOk flight=$fFlight crew=$fCrew booking=$fBook" }
        }
    }

    8 = @{
        Title = 'Boarding Resumes: Brief Airline Leadership'
        Kind  = 'config'
        Start = {
            Write-Host "The platform is stable and boarding has resumed. Close out the major incident." -ForegroundColor Gray
            Write-Host "Produce an engineering RCA handover (with change evidence) and a leadership briefing"
            Write-Host "(impact, root cause, recovery, risk, lessons), then have the agent render the briefing as a PDF with a"
            Write-Host "timeline chart. Distinguish symptom, root cause, mitigation and corrective action."
        }
        Check = {
            $s = Get-AetherionStatus
            $allOk = $true
            foreach ($p in $s.services.PSObject.Properties) { if (-not $p.Value.ok) { $allOk = $false } }
            if (-not $allOk) { return @{ Pass = $false; Detail = "platform not fully healthy yet (overall=$($s.overall)) - resolve challenge 7 first" } }
            $done = Confirm-SelfAttest 'Have you produced an executive leadership briefing AND an engineering RCA handover for the major incident?'
            @{ Pass = ($allOk -and $done); Detail = "platform healthy=$allOk, briefing + handover produced=$done" }
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
        if (-not $script:Challenges.Contains($Number + 1)) {
            Write-Host "  That was the final challenge - you have restored Aetherion AirOps. Well flown." -ForegroundColor Green
        }
        Write-Host ""
        return $true
    }
    else {
        Write-Host "  NOT YET - the incident is still active." -ForegroundColor Yellow
        Write-Host "  Keep investigating with your SRE Agent, then re-run this check." -ForegroundColor Gray
        Write-Host ""
        return $false
    }
}
