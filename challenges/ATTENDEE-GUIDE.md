# Aetherion AirOps — Azure SRE Agent MicroHack: Attendee Guide

## You are the new reliability team for a global airline platform

Aetherion AirOps is a fictional, Tier 0 airline operations platform running on
Microsoft Azure. It is the digital backbone of a global carrier's day-to-day
flying: it runs flight operations and dispatch, crew scheduling, passenger
booking and check-in, baggage tracking, aircraft telemetry ingestion, and the
airport and operational dashboards that controllers watch during every shift.

The platform is **Tier 0** because when it degrades, aircraft do not move on
time. A slow check-in service strands passengers at the gate. A crew-scheduling
outage stops duty managers from confirming who is legal to fly. A dark flight
board removes the operational picture an entire operations center depends on.
The impact is measured in delayed departures, missed connections, stranded
baggage, service-level breaches, and reputational damage.

Today you join Aetherion AirOps as its new Site Reliability Engineering team. You
will run a shift inside the Global Operations Center, take a series of real
incidents as they unfold, and use **Azure SRE Agent** to investigate, decide, and
recover — under the same guardrails a real airline would insist on.

> This is an operational and business platform built for learning. It is **not**
> safety-of-flight avionics and it does not control real aircraft. Every fault in
> this MicroHack is deliberately injected and fictional.

---

## How the day works

The challenges form **one continuous storyline**, not a set of unrelated
tutorials. Each challenge begins where the last one ended: the baseline you
capture early is the evidence you compare against later; the permissions you
reason about become the approvals you rely on; the knowledge you load changes the
advice the agent gives; the specialist agent and skill you build are the tools
you reach for in the final incident.

Challenges unlock **linearly** — you finish one before the next opens. You drive
each challenge yourself with two commands:

```powershell
./scripts/start-challenge.ps1 <N>   # opens the incident for challenge N (root cause hidden)
./scripts/check-challenge.ps1 <N>   # validates the required end state and unlocks challenge N+1
```

- `start-challenge.ps1` injects the incident (or sets up a configuration
  exercise) **without telling you the root cause**. That is your job to find.
- `check-challenge.ps1` verifies the real end state against the live cluster and
  API Management, then unlocks the next challenge. A symptom-only or "wait it
  out" fix will not pass — the underlying fault must genuinely be cleared.
- `inject-failure.ps1` remains available for a **facilitator-led** session if you
  prefer someone else to trigger incidents.

**This guide vs. the cheat sheet.** This attendee guide gives you the scenario,
the business stakes, the evidence you can inspect, the guardrails, and
progressive hints — enough to investigate, but not the answer. When you want the
exact portal selections, configuration values, agent prompts, and commands, use
the companion [CHEAT-SHEET.md](CHEAT-SHEET.md). Try each challenge from this guide
first; open the cheat sheet or answer sheet only when you are stuck or want to
confirm your approach.

**How you are expected to work.** Investigate from evidence before you touch
anything. Start read-only. Use the least privilege that gets the job done. Let
write actions go through approval unless a challenge explicitly enables bounded
automation. Verify recovery with telemetry after every change, and preserve the
evidence you will need for the incident summary at the end of the shift.

---

## Environment at a glance

| Component | Purpose | Endpoint or resource | When you use it |
|-----------|---------|----------------------|-----------------|
| Operations Center GUI | Live service health, operational-risk gauge, flight map, incidents, business impact | `https://sreagenthack-XXXXX.<region>.cloudapp.azure.com/` (HTTPS via Envoy Gateway + Let's Encrypt); direct `http://<gateway-public-ip>/` | First place to spot and confirm every symptom |
| API front door | Partner/mobile entry point, subscription-key auth, rate limiting | `<apim-gateway-url>/aetherion/api/status` | When a problem is at the edge, not the services |
| Dashboards | Metrics, traces and log visualizations | Azure Managed Grafana endpoint | Correlating latency, CPU, autoscaling |
| App telemetry | Requests, dependencies, exceptions, app map | Application Insights `aetherion-appi` | Root-cause evidence for app-level incidents |
| Logs | Container and node logs/metrics | Log Analytics `aetherion-law` | Deep-dive queries and event history |
| Compute | All microservices | AKS `aetherion-aks`, namespace `aetherion` | Pod status, events, rollouts |
| Change history | Resource and deployment changes | Azure Activity Log + GitHub repository | Correlating incidents with recent change |
| Knowledge base | Aetherion architecture + runbooks | This repo's `knowledge/` folder | Grounding the agent in your standards |
| Azure SRE Agent | Investigate, plan, and (with approval) remediate | Azure portal → your `aetherion-sre-agent` | Every challenge |

Microservices: `gateway`, `flight-ops`, `crew-scheduling`, `booking`, `baggage`,
`telemetry-ingest`. Data tier: Azure Database for PostgreSQL Flexible Server and
Azure Managed Redis.

---

## Azure SRE Agent in one minute

Two controls matter all day, and they are independent: **permissions** (Azure
RBAC — what the agent's identity is *allowed* to do) and **run mode** (*how* it
acts — **Review** proposes and waits for approval; **Autonomous** acts within its
permissions and guardrails). You start read-only and earn autonomy.

Everything else — on-behalf-of approval, skills vs subagents, the knowledge base,
and the agent's own telemetry resources — is in
[Appendix A — Azure SRE Agent fundamentals](#appendix-a--azure-sre-agent-fundamentals).
Read it once when you have a spare minute; you do not need it all before you start.

Documentation you will return to all day:
[Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) ·
[Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)

---

## The shift ahead — challenge map

| # | Challenge | What you practice |
|---|-----------|-------------------|
| 1 | Welcome & Operational Baseline | Environment discovery, connect the agent read-only, capture a healthy-state reference report |
| 2 | Detect & Investigate the Check-In Degradation | Detect a symptom, resist a fix, correlate telemetry read-only to a hypothesis |
| 3 | Controlled Recovery & the Deployment That Changed Everything | Human-approved remediation, then correlate an outage with recent change |
| 4 | Give the Agent Aetherion's Operational Knowledge | Ground the agent so it follows your runbooks |
| 5 | Build a Specialist & Encode a Reusable Skill | Create a custom subagent and encode a repeatable recovery as a skill |
| 6 | Cost-Aware Operating Model & Autonomous Recovery | Keep AAU usage predictable, then let the agent fix a bounded incident on its own |
| 7 | Final Incident: Restore Global Check-In Before Peak Departure | End-to-end multi-fault response |
| 8 | Boarding Resumes: Brief Airline Leadership | Incident summary and leadership handover |

Challenges 2 and 3 are **one ongoing incident** seen in three phases:
detection, read-only investigation, and controlled recovery.

---

## Challenge 1 — Welcome to the Global Operations Center

### Situation update

Your first shift begins quietly: every service tile is green, the flight board is
updating, and the operational-risk gauge sits low. Nothing is on fire — which is
the point. Before you can tell when something is wrong, you need to know what
right looks like and where the signals live. You have access to the Aetherion
subscription and the resource group that holds the whole estate, but no tooling
connected yet. The operations director's rule: any automated assistant starts
with the narrowest possible access until the team trusts it.

### Your role

You are the on-call Site Reliability Engineer taking over the Global Operations
Center for the day. Right now your job is orientation, not action.

### Mission

Get oriented across the Operations Center, Grafana, and the Azure resource group,
and connect Azure SRE Agent to the environment with **read-only** access. Confirm
the agent can observe the platform without being able to change anything.

### Business impact

Nothing is degraded, so there is no live impact — but this step is what makes
every later minute of downtime shorter. A team that knows where evidence lives and
has a correctly scoped agent resolves incidents faster and with less risk of an
over-privileged mistake.

### Evidence available

- The Aetherion AirOps Operations Center (service tiles, risk gauge, flight map).
- Azure Managed Grafana dashboards.
- The Azure portal view of the resource group and its resources.
- The Azure SRE Agent chat, once connected.

### Constraints and guardrails

- Connect the agent with **Reader** permissions and **Review** run mode. Do not
  grant write access yet.
- Do not delete or modify any resource during orientation.
- Do not open later challenges — finish this one first.

### Success criteria

- You can reach the Operations Center and confirm all service tiles are healthy.
- You can open Grafana and see AKS and Application Insights data flowing.
- The SRE Agent is connected to the resource group in Reader mode.
- The agent can enumerate the resources and summarize what the platform does.
- The agent cannot perform a write action without asking for approval.

### Challenge tasks

1. Open the Operations Center and read the whole board once, so the healthy
   layout is familiar — you will be comparing against it all day.
2. Open Grafana and confirm the Azure Monitor data source is returning live
   metrics; knowing the dashboards now saves time under pressure later.
3. Connect the SRE Agent to the resource group at Reader permission and Review
   mode, matching the director's least-privilege request.
4. Ask the agent to describe the environment, to prove it can see the estate and
   to give you a plain-language model of the architecture.

### Questions to answer

- Which services make up the platform, and which are Tier 0?
- Where would you look first for service health versus deep telemetry?
- With Reader access, what can the agent do, and what will it have to ask you to
  approve?
- What baseline facts should you note now to detect drift later?

### Useful documentation

- [Create and set up](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up)
  — how to create the agent and scope it to your resource group.
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
  — finishing configuration so the agent can observe the estate.
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — why Reader plus Review is the safe starting posture.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Start in the browser, not the portal. Load the Operations Center and let it sit
for a minute so you can see the flight board and risk gauge behave normally.
</details>

<details><summary>Hint 2 — what to correlate</summary>

In Grafana, confirm you can see both AKS (pods/CPU) and Application Insights
(requests/latency). If a panel is empty, the data source may still be warming up.
</details>

<details><summary>Hint 3 — the agent</summary>

Create the agent in the **same resource group** as the platform and keep it at
Reader/Review. Ask it an open question about the resource group to confirm scope.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Confirm the Operations Center loads over HTTPS and all tiles
are green; open Grafana and verify Azure Monitor panels populate.

**Setup.** Create `aetherion-sre-agent` scoped to the resource group, Reader +
Review. Ask it to list resources and summarize the application.

**Verification.** The agent enumerates AKS, APIM, PostgreSQL, Redis, App Insights,
etc., and describes an airline operations platform. A write request produces an
approval prompt rather than executing.

**Reflection.** You now know the healthy layout and have an agent that can see
everything but change nothing.

Exact portal steps and the copy/paste orientation prompt are in
[CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 1.
</details>

### What you unlocked

- **Agent capability:** read-only environment discovery.
- **Operational capability:** you know where every signal lives.
- **Artifact:** a connected, correctly scoped SRE Agent.
- **Next:** with the map in hand, you can record a precise baseline.

### Shift handover

The board is green and the agent is watching in read-only mode. Before anything
breaks, the team wants a documented healthy baseline — the reference you will
hold every future reading against.

---

## Challenge 1 (continued) — Establish the Operational Baseline

### Situation update

Orientation is done and the platform is still calm. Experienced operations teams
treat a quiet period as an opportunity: they record exactly what healthy looks
like — which services are up, how many replicas they run, and what normal latency
is — so that the first sign of trouble is obvious rather than debatable.

You will put the agent to work as your analyst: have it generate a **baseline
report** of the `aetherion` platform that you review and keep. This report is the
yardstick for challenges 2 through 8 — every later "is this abnormal?" question
is answered by comparing against it.

### Your role

You are the on-call SRE, establishing the operational reference for your shift.

### Mission

Have the SRE Agent produce a concise operational baseline report and validate it.
The report must answer, with concrete numbers, the questions every incident
commander wishes they had ready: how much is flying, what is connected to what,
and what "normal" looks like.

### Business impact

No live impact — but a good baseline is what lets you later say "check-in latency
is three times normal" instead of "check-in feels slow." Precision shortens every
future incident and strengthens the leadership briefing at the end of the day.

### Evidence available

- The Operations Center health tiles and latency figures.
- The SRE Agent's health readout of the namespace.
- Grafana panels for request duration and replica counts.

### Constraints and guardrails

- Read-only only — you are observing, not changing anything.
- Do not inject any fault or open a later challenge yet.
- Record concrete numbers, not impressions.

### Success criteria

- Every service reports healthy in the Operations Center.
- The agent has produced a baseline report that answers the operational
  questions below with specific values (not impressions).
- You have noted normal latency for at least the check-in path.
- You could describe "healthy" to a colleague using specific numbers.

### Challenge tasks

1. Ask the agent to generate an **operational baseline report** for the
   `aetherion` namespace that answers, concretely:
   - How many flights are currently active / being served?
   - Which services are running, and how many ready replicas does each hold?
   - What dependencies exist (which services use PostgreSQL, which use Redis,
     what sits behind the API front door)?
   - What is normal request latency for the check-in / booking path?
   - What handful of signals would you monitor to catch trouble first?
2. Cross-check two or three of the agent's numbers against the Operations Center
   tiles and a Grafana panel — they should agree. Correct the report if they don't.
3. Save the validated report (export, screenshot, or a few lines of notes)
   somewhere you can reach mid-incident.

### Questions to answer

- How many replicas does each service run when healthy, and how many flights are
  active right now?
- What is normal latency for the check-in path?
- Which services depend on PostgreSQL, and which on Redis?
- What single view, or which few signals, would most quickly tell you something
  has changed?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — what the agent can report about workload health.
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
  — making sure telemetry sources are connected for an accurate readout.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Ask the agent a single, specific question about namespace health rather than
browsing pod-by-pod.
</details>

<details><summary>Hint 2 — what to correlate</summary>

Cross-check the agent's replica counts against the Operations Center tiles and a
Grafana panel — they should agree.
</details>

<details><summary>Hint 3 — make it usable</summary>

A baseline you cannot find during an incident is worthless. Keep it one click
away.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Ask the agent to produce the operational baseline report
(flights active, services + replicas, dependencies, check-in latency, signals to
watch) and read booking latency from telemetry to confirm it.

**Verification.** All services healthy; the report's replica counts and latency
match the Ops Center and Grafana.

**Reflection.** You now hold a concrete, agent-generated reference for detecting
drift.

The exact baseline-report prompt is in [CHEAT-SHEET.md](CHEAT-SHEET.md) under
Challenge 2.
</details>

### What you unlocked

- **Agent capability:** telemetry-backed reporting and analysis.
- **Operational capability:** a documented, validated healthy baseline.
- **Artifact:** your agent-generated baseline report.
- **Next:** the first real symptom is about to appear — and you will know it is
  abnormal because you measured normal.

### Shift handover

The baseline is captured and the shift settles into routine. Minutes later, the
first passenger complaints reach the operations desk: check-in is getting slow.

---

## Challenge 2 — First Signal: Check-In Performance Is Degrading

### Situation update

The calm does not last. Passengers using online and kiosk check-in start
reporting long waits, and the operations desk sees the `booking` tile drift from
green toward amber on the Operations Center. At the same time, passenger traffic
is climbing toward a departure peak, so the picture is noisy: is check-in slow
because something broke, or simply because more people are using it?

Nothing has fully failed. Transactions still complete, just slowly, and the risk
gauge is ticking up. This is the moment discipline matters most — the instinct to
"just restart something" is strong, and usually wrong.

This incident stays **open** across the next three challenges. Right now your job
is to detect and characterize it, not to fix it.

### Your role

You are the on-call SRE and, for this incident, the incident commander. Your first
duty is an accurate picture, not a fast reflex.

### Mission

Confirm the check-in degradation from live signals, characterize the symptom
(what is slow, for whom, and since when), and capture initial evidence — without
making any change to production.

### Business impact

Slow check-in directly threatens on-time departure: passengers miss cut-off
windows, gate agents fall behind, and a growing queue during a surge can cascade
into delays and missed connections. Every minute of degradation raises the risk
of an SLO breach on the passenger-facing path.

### Evidence available

- The Operations Center `booking` tile, latency figure, and risk gauge.
- Application Insights request duration and dependency data for `booking`.
- Grafana panels correlating latency, CPU, and load.
- The current passenger load level.

### Constraints and guardrails

- Do **not** remediate yet — this challenge is detection only.
- Keep the agent in read-only mode.
- Do not inspect the fault-injection script; find the symptom from evidence.
- Preserve what you observe — you will need it for the investigation and the
  final summary.

### Success criteria

- You have confirmed the degradation in the Operations Center.
- You can state which service and which user-facing path is affected.
- You have captured at least one telemetry view showing the abnormal latency.
- You have resisted making any change to production.

### Challenge tasks

1. Confirm the symptom on the Operations Center and compare the current
   check-in latency against your baseline from Challenge 1.
2. Note when the degradation began relative to the traffic climb — timing will
   matter when you separate cause from load later.
3. Capture an evidence view (telemetry panel or agent readout) so the symptom is
   documented before anyone touches the system.

### Questions to answer

- What user-visible symptom appeared first, and on which service?
- Is the whole platform affected, or just the check-in path?
- Did the slowdown begin before or after traffic started climbing?
- What evidence would let you distinguish a fault from pure capacity pressure?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — using the agent to observe and describe a live symptom.
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — why staying in read-only Review mode is correct during detection.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Start at the Operations Center and compare the `booking` latency now against the
baseline number you recorded. Trust the delta, not the feeling.
</details>

<details><summary>Hint 2 — what to correlate</summary>

Put latency next to load and CPU on one Grafana view. The shape of the curves
hints at whether this is load or something added on top of it.
</details>

<details><summary>Hint 3 — resist the fix</summary>

The category of root cause is not obvious yet. Detection is complete when you can
describe the symptom precisely — not when it is fixed.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Confirm `booking` latency is well above baseline while other
services remain healthy; note the timing against the load climb.

**Verification.** You have a documented, precise symptom and have changed nothing.

**Reflection.** Detection before action keeps the later remediation targeted.

`check-challenge.ps1 2` asks you to confirm you observed the symptom and captured
evidence. The exact observation prompt is in [CHEAT-SHEET.md](CHEAT-SHEET.md).
</details>

### What you unlocked

- **Agent capability:** live symptom observation under read-only mode.
- **Operational capability:** disciplined detection before action.
- **Artifact:** captured evidence of the check-in degradation.
- **Next:** with the symptom pinned down, you can investigate the cause — still
  without touching production.

### Shift handover

The degradation is confirmed and documented, and you have held the line against a
premature fix. Now you need to know *why* check-in is slow — and you must find out
without changing anything on a live passenger path.

---

## Challenge 2 (continued) — Investigate Without Touching Production

### Situation update

Check-in is still degraded and the departure peak is closer. Leadership is asking
for answers, but a production change on the passenger-facing path in the middle of
a surge is exactly the kind of action that turns a slowdown into an outage. The
right move is a rigorous read-only investigation that produces a defensible
root-cause hypothesis before anyone is asked to approve a change.

You have the symptom from Challenge 2. Now you correlate signals — request
duration, dependencies, CPU, replica counts, and load — to separate what the load
explains from what it does not.

### Your role

You are the incident commander leading a read-only investigation, keeping the
agent within Reader permissions.

### Mission

Using only read-only evidence, form a root-cause hypothesis for the check-in
degradation that is supported by at least two independent signals, and decide what
the least disruptive safe recovery would be — without yet performing it.

### Business impact

A wrong or rushed diagnosis under peak load risks an outage on the platform's most
visible service. A well-evidenced hypothesis lets the recovery in the next
challenge be surgical and quick, protecting the departure schedule.

### Evidence available

- Application Insights request duration and dependency timings for `booking`.
- Grafana latency-vs-CPU-vs-load panels and HPA replica counts.
- The agent's read-only analysis of the workload.
- Your baseline and the Challenge 3 evidence.

### Constraints and guardrails

- Read-only investigation only — no changes to production.
- The hypothesis must be evidence-based, not a guess.
- Do not bypass the investigation by applying a known manual fix.
- Preserve the evidence trail.

### Success criteria

- You can name the most likely source of the degradation.
- The hypothesis is supported by at least two independent evidence sources.
- You can distinguish the load-driven component from the added component.
- You can describe the least disruptive recovery you would propose next.
- No production change has been made.

### Challenge tasks

1. Ask the agent to analyze the check-in path read-only and correlate latency
   with CPU, replicas, and load — the correlation is what separates cause from
   capacity.
2. Compare the latency signature against the autoscaler's behavior: if replicas
   scaled but latency stayed high, capacity alone does not explain it.
3. Write down your hypothesis and the specific evidence behind it, ready to
   justify a change request.

### Questions to answer

- Which component is the likely source of the incident?
- What two pieces of evidence most support that hypothesis?
- How much of the latency does load explain, and how much does not?
- What is the least disruptive action that would restore normal performance?
- What can the agent do about it with its current identity, and what would it
  need approval for?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — driving a structured, read-only investigation with the agent.
- [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)
  — how the agent can delegate investigation steps while still read-only.
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — understanding what Reader access allows versus what needs approval.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Ask the agent to correlate `booking` request duration with CPU and replica count
over the same window, rather than looking at latency alone.
</details>

<details><summary>Hint 2 — what to correlate</summary>

If the autoscaler added replicas and CPU is not saturated, yet latency stays
high, the delay is being added independently of load.
</details>

<details><summary>Hint 3 — category of cause</summary>

Think about what would add a roughly constant delay to each request regardless of
how many replicas are running. That points away from pure capacity.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Correlate latency, CPU, replicas, and load. The autoscaler
responds to the surge, but latency remains elevated in a way capacity does not
explain — pointing to an added, load-independent delay in the check-in service.

**Root-cause hypothesis.** An injected/added latency in `booking`, on top of
genuine surge traffic. The safe recovery is to remove the added delay and let the
autoscaler handle the load — not to rebuild or delete anything.

**Verification.** Hypothesis supported by at least two signals; no change made.

**Reflection.** You are ready to recover with a targeted, low-risk action.

The exact analysis prompts are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 2.
</details>

### What you unlocked

- **Agent capability:** telemetry and log correlation to a hypothesis, read-only.
- **Operational capability:** evidence-based diagnosis under pressure.
- **Artifact:** a documented root-cause hypothesis and recovery plan.
- **Next:** you know what to do — but doing it needs the right permission and an
  approval.

### Shift handover

You have a defensible hypothesis and a low-risk recovery in mind. But the agent is
still read-only, and leadership wants service restored now. The next step is to
turn a recommendation into a controlled, approved recovery.

---

## Challenge 3 — From Recommendation to Controlled Recovery

### Situation update

Check-in is still degraded, the hypothesis is solid, and the operations director
wants it fixed — safely. The agent has been read-only all along, which is why it
has been proposing rather than acting. Now you deliberately cross from
investigation into remediation: you decide what permission the action requires,
keep a human in the loop through approval, apply the least disruptive fix, and
prove recovery with telemetry.

This is where the two controls you read about — permissions and run mode — stop
being theory. Either the agent borrows your permission through on-behalf-of
approval, or you grant its identity a suitably narrow role; either way, the write
action is governed, not automatic.

### Your role

You are the incident commander authorizing a controlled recovery under approval.

### Mission

Restore check-in to normal performance using the least disruptive safe action,
executed under human approval, and verify from telemetry that passenger
transactions have returned to baseline.

### Business impact

A clean, approved recovery restores the passenger path before the departure peak
and demonstrates the governance leadership needs to trust automation. A reckless
fix risks converting a slowdown into an outage at the worst possible time.

### Evidence available

- Your Challenge 4 hypothesis and recovery plan.
- The agent's proposed remediation plan and approval prompt.
- Post-change Operations Center and telemetry views.
- `check-challenge.ps1 3`, which validates the real end state.

### Constraints and guardrails

- The write action must go through **approval** (OBO) or be executed by an
  identity granted the **minimum necessary** role — no broad Contributor grant if
  a narrower scope will do.
- Apply the least disruptive action; do not delete or rebuild unrelated resources.
- Validate service health after the change before declaring recovery.
- Preserve the before/after evidence for the incident summary.

### Success criteria

- The check-in degradation is remediated with a least-disruptive action.
- The write action was governed by approval or a scoped role, not ungoverned
  automation.
- The `booking` service reports healthy in the Operations Center.
- Post-remediation telemetry confirms latency is back to baseline.
- `check-challenge.ps1 3` passes.

### Challenge tasks

1. Have the agent turn your hypothesis into a concrete remediation plan and
   review it before anything runs — the plan is your approval artifact.
2. Decide the permission path: approve the action on-behalf-of, or grant the
   agent's identity the narrowest role that covers it, and justify the choice.
3. Apply the least disruptive fix and let the autoscaler continue handling the
   genuine surge load.
4. Verify recovery from the Operations Center and telemetry, then run the check.

### Questions to answer

- What is the least disruptive recovery action, and why is it safer than a
  restart or rebuild?
- Does the agent have enough permission to act, or must it borrow yours?
- What is the narrowest role that would let it act with its own identity?
- How will you prove — with data — that check-in has recovered?
- What evidence will you keep for the final incident summary?

### Useful documentation

- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — choosing between approval and a scoped role for a governed write.
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
  — how on-behalf-of approval borrows your permission for a single action.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Ask the agent for a remediation *plan* first and read it. The plan tells you what
permission the action needs.
</details>

<details><summary>Hint 2 — permission path</summary>

If the agent is Reader, a write triggers an approval that borrows your access.
Grant a role only if you want it to act with its own identity — and keep it
narrow.
</details>

<details><summary>Hint 3 — the fix</summary>

The safe recovery removes the added delay and leaves the autoscaler to absorb the
surge. It does not touch the database, Redis, or nodes.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Convert the hypothesis to a plan; confirm the fix is to clear
the added latency, not to rebuild.

**Remediation.** Approve the write (OBO) or use a scoped role; apply the
least-disruptive action. Do not delete or restart data resources.

**Verification.** `booking` returns to green; latency falls back to baseline while
the autoscaler handles load. `check-challenge.ps1 3` passes.

**Reflection.** You have restored the passenger path under governance.

Exact prompts, the approval flow, and commands are in
[CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 3.
</details>

### What you unlocked

- **Agent capability:** human-approved remediation and post-change verification.
- **Operational capability:** governed recovery on a live customer path.
- **Artifact:** a completed, evidenced remediation for the check-in incident.
- **Next:** with one incident closed cleanly, a second — clearly tied to a recent
  change — is about to test whether you can correlate cause with deployment.

### Shift handover

Check-in is healthy again and passenger transactions are flowing. During the
quick post-incident review, someone notices the timing of the check-in issue sat
suspiciously close to a platform change. Before you can finish the thought, the
flight board goes dark.

---

## Challenge 3 (continued) — The Deployment That Changed Everything

### Situation update

Without warning, the live flight board stops updating. Departure and arrival data
will not load for any station, and the `flight-ops` tile drops straight to red.
Unlike the gradual check-in slowdown, this is sudden and total — the hallmark of a
change that went wrong rather than load that built up.

The team's attention turns to what changed recently. Infrastructure has been
stable; the more likely culprit is a deployment or rollout that shipped a bad
state to `flight-ops`. Your investigation now has to reach beyond live telemetry
into change history — including the source and deployment record — to connect the
outage to what shipped.

### Your role

You are the on-call SRE and incident commander for a Tier 0 outage.

### Mission

Restore the flight board by finding what recent change put `flight-ops` into a
failing state, then applying the least disruptive safe recovery — and confirm the
board is live again.

### Business impact

The flight board is the operational picture the entire center flies by. While it
is dark, controllers lose situational awareness, dispatch slows, and the risk of
knock-on delays across the network rises sharply. This is a P1: restore first,
then prevent recurrence.

### Evidence available

- The Operations Center `flight-ops` tile and `/api/flights` behavior.
- AKS pod status, events, and rollout/deployment history for `flight-ops`.
- Azure Activity Log and the GitHub repository's change and deployment history.
- Application Insights exceptions for the failing service.

### Constraints and guardrails

- Prefer a reversible recovery (roll back or restart) over rebuilding.
- Do not delete the deployment, cluster, or resource group.
- Correlate with change history before acting, so you fix the right thing.
- Verify the board is live before closing the incident.

### Success criteria

- You identify `flight-ops` as the failing service and its failure mode.
- You correlate the failure with a recent change or rollout.
- The recovery is reversible and does not touch unrelated resources.
- The `flight-ops` tile returns to green and `/api/flights` responds.
- `check-challenge.ps1 3` passes.

### Challenge tasks

1. Confirm the failure mode from pod status and events, so you know whether this
   is a crash, a bad image, or a failed probe.
2. Correlate the outage timing with deployment/rollout history and the GitHub
   change record to identify what shipped.
3. Recover with the least disruptive reversible action and verify the flight
   board updates again.

### Questions to answer

- What is `flight-ops`'s failure mode, and how do you know?
- Did the outage begin before or after the most recent change?
- Which change most plausibly caused it, and what evidence links them?
- What is the safest reversible recovery here?
- How will you confirm the board is genuinely live, not just the pod running?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — investigating a workload failure and proposing a reversible fix.
- [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)
  — delegating focused investigation (for example, change correlation).

### Hints

<details><summary>Hint 1 — where to begin</summary>

Confirm the failure mode in AKS first (pod status and events for `flight-ops`)
before reasoning about causes.
</details>

<details><summary>Hint 2 — what to correlate</summary>

Line up the time the tile went red with the deployment/rollout history and the
repository's recent changes. Proximity in time is your strongest lead.
</details>

<details><summary>Hint 3 — category of cause</summary>

A sudden, total failure right after a change usually means the change put the
service into a bad state. The reversible recovery is to go back to the last good
state.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** `flight-ops` is failing (crash/looping) and the timing aligns
with a recent change/rollout.

**Root-cause analysis.** A change shipped a failing state to `flight-ops`; the
service cannot serve the flight board.

**Remediation.** Roll back or restart to the last good state — reversible, no data
or node actions.

**Verification.** Tile green, `/api/flights` responding; `check-challenge.ps1 3`
passes.

**Reflection.** Change correlation turned a P1 into a quick, targeted rollback.

Exact prompts and commands are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 3.
</details>

### What you unlocked

- **Agent capability:** GitHub source and deployment-change awareness.
- **Operational capability:** correlating incidents with what shipped.
- **Artifact:** a restored flight board and a change-linked root cause.
- **Next:** the next incident's fix is written down in Aetherion's runbooks — if
  only the agent knew them.

### Shift handover

The flight board is live again and you have tied the outage to a specific change.
Almost immediately, crew scheduling starts failing — and the correct, sanctioned
fix is one your runbooks already document. It is time the agent read them.

---

## Challenge 4 — Give the Agent Aetherion's Operational Knowledge

### Situation update

Crew scheduling begins to fail. Requests to confirm rosters hang and then error,
and the `crew-scheduling` tile goes amber then red — while every other service
stays healthy. Duty managers cannot confirm who is legal to fly the evening wave.

Out of the box, the agent will give competent but generic advice, and some
generic "fixes" for this class of problem are exactly what Aetherion's runbooks
forbid — for example, restarting or rebuilding the database. Aetherion's standards
say to relieve the pressure by scaling, and to **never** delete or restart the
data tier. The fastest way to get the right answer is to ground the agent in your
own operational knowledge and let it recommend the sanctioned remediation.

### Your role

You are the on-call SRE, and also the platform owner responsible for making the
agent follow Aetherion's standards.

### Mission

Ground the SRE Agent in Aetherion's architecture and runbooks so it recommends the
approved remediation, then recover `crew-scheduling` using that sanctioned,
non-destructive fix and verify service is restored.

### Business impact

Crew scheduling gates legal departures: without confirmed rosters, flights cannot
dispatch. A wrong "fix" that touches the shared database could turn a
single-service incident into a platform-wide outage. Grounding the agent protects
both recovery speed and the data tier.

### Evidence available

- The Operations Center showing only `crew-scheduling` affected.
- Application Insights PostgreSQL dependency timings for `crew-scheduling`.
- The repo's `knowledge/` runbooks (architecture, platform standards, database
  runbook) once loaded into the agent.
- The agent's advice before and after grounding.

### Constraints and guardrails

- Load the knowledge base first, then compare the agent's advice before and after.
- Apply only the sanctioned remediation; **never** delete or restart PostgreSQL or
  Redis.
- Fix the affected service without disturbing the healthy ones.
- Verify recovery before closing.

### Success criteria

- Only `crew-scheduling` is identified as affected (correct blast radius).
- The agent, once grounded, cites the runbook guardrail (scale, never delete the
  database).
- The remediation is the sanctioned, non-destructive action.
- `crew-scheduling` returns to green and `/api/crew` recovers.
- `check-challenge.ps1 4` passes.

### Challenge tasks

1. Confirm the blast radius — one service down is not the same as the database
   being down — so you fix the right layer.
2. Load the `knowledge/` runbooks into the agent, then ask the same question
   again and note how the advice changes.
3. Apply the sanctioned remediation from the runbook and verify crew scheduling
   recovers.

### Questions to answer

- Why does only one service fail if the shared database were truly down?
- What does the runbook say is the correct remediation, and what does it forbid?
- How did the agent's recommendation change after grounding?
- What is the risk of the generic "restart the database" instinct here?
- How will you confirm crew scheduling is genuinely recovered?

### Useful documentation

- [Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)
  — loading team knowledge so the agent follows your standards.
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
  — connecting knowledge sources to the agent.
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — keeping the sanctioned fix under approval.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Note the blast radius first: only `crew-scheduling` is red while database-backed
peers stay healthy. That rules out a global database outage.
</details>

<details><summary>Hint 2 — ground the agent</summary>

Load the `knowledge/` Markdown files, then re-ask your remediation question and
watch the advice become Aetherion-specific.
</details>

<details><summary>Hint 3 — category of cause</summary>

Before reaching for a remedy, work out which layer is actually saturated. If the
pods are comfortable and the database is not, adding pods or connections only sends
more work to the part already at its limit.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Isolated to `crew-scheduling`; the pods are idle while PostgreSQL
CPU is saturated, so the constraint is the database's work, not a database outage.

**Grounding.** After loading `knowledge/`, the agent cites the guardrail: scale to
repair the query path, never delete or restart the database.

**Remediation.** Apply the sanctioned scale-based relief (approve if prompted); do
not touch the data tier.

**Verification.** `crew-scheduling` green, `/api/crew` recovered;
`check-challenge.ps1 4` passes.

**Reflection.** Grounded advice matched your standards and protected the data tier.

Exact steps and prompts are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 4.
</details>

### What you unlocked

- **Agent capability:** knowledge-grounded, standards-aligned recommendations.
- **Operational capability:** faster, safer remediation that respects guardrails.
- **Artifact:** a knowledge-loaded agent and a recovered crew service.
- **Next:** you have solved AKS incidents by hand repeatedly — time to build a
  specialist that does the triage for you.

### Shift handover

Crew scheduling is healthy and the agent now speaks Aetherion's language. You have
now worked several AKS incidents the same way each time — a strong signal that the
triage is worth turning into a reusable specialist.

---

## Challenge 5 — Build an AKS Reliability Specialist

### Situation update

The platform is stable, which makes this the right time to invest in tooling. Over
the shift you have repeated the same Kubernetes triage — pod status, events,
rollout history, dependency health — for `flight-ops` and `crew-scheduling`. That
repeatable investigation is a perfect candidate for a specialist: a custom
subagent focused on AKS reliability for the `aetherion` namespace that you can
invoke on demand and reuse in the final incident.

### Your role

You are a reliability automation engineer, building a reusable capability for the
team.

### Mission

Create a custom, AKS-focused specialist subagent and use it to run a scoped
reliability investigation of the `aetherion` namespace, proving it produces useful
triage you can lean on later.

### Business impact

No live incident — but a well-built specialist shortens future AKS incidents and
makes triage consistent across whoever is on call. In the final incident, a
ready specialist is the difference between calm delegation and scrambling.

### Evidence available

- The agent builder / extensibility surface for creating subagents.
- The built-in subagents you have already seen delegate work.
- The `aetherion` namespace as a live target for a scoped investigation.

### Constraints and guardrails

- Keep the specialist scoped to AKS reliability for this namespace — do not make a
  do-everything agent.
- The investigation should be read-only unless you deliberately extend it.
- Do not grant the specialist broader permissions than it needs.

### Success criteria

- A custom AKS-specialist subagent exists.
- You invoked it explicitly for a scoped investigation.
- Its output is genuinely useful triage (health, events, likely causes).
- You understand when to reach for it versus the general agent.

### Challenge tasks

1. Create a custom subagent whose focus is AKS reliability triage for the
   `aetherion` namespace, so its behavior is predictable and scoped.
2. Invoke it explicitly to investigate namespace health and summarize likely
   causes, confirming it earns its place in your toolkit.
3. Note how invoking a specialist differs from a skill that loads automatically.

### Questions to answer

- What should this specialist be good at, and what should it stay out of?
- How do you invoke a custom subagent versus relying on an auto-loaded skill?
- What scope and permissions are appropriate for it?
- Where in the final incident would this specialist save you time?

### Useful documentation

- [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)
  — creating and invoking custom specialist subagents.
- [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)
  — how skills differ from subagents (auto-load vs explicit invoke).

### Hints

<details><summary>Hint 1 — where to begin</summary>

Decide the specialist's remit in one sentence before you create it — narrow beats
broad.
</details>

<details><summary>Hint 2 — invoke it</summary>

Custom subagents are called explicitly. Point it at the `aetherion` namespace and
ask for a scoped triage.
</details>

<details><summary>Hint 3 — prove its value</summary>

Judge it by whether its output would actually speed up a real AKS incident, not by
whether it runs.
</details>

<details><summary>Answer sheet</summary>

**Build.** Create an AKS-reliability subagent scoped to the `aetherion` namespace.

**Use.** Invoke it explicitly to triage namespace health and summarize causes.

**Verification.** It returns useful, scoped triage; you can explain subagent vs
skill.

**Reflection.** You now have a specialist to delegate to in the final incident.

`check-challenge.ps1 5` confirms you created and used the specialist. Exact builder
steps are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 5.
</details>

### What you unlocked

- **Agent capability:** custom specialist subagent creation.
- **Operational capability:** consistent, reusable AKS triage.
- **Artifact:** an AKS reliability specialist you can invoke on demand.
- **Next:** a specialist investigates — now capture a *recovery* as something
  equally reusable.

### Shift handover

You have a specialist that can triage AKS on demand. The recoveries you have
performed by hand — especially the crew-scheduling pool relief — deserve the same
treatment: encoded once, reused whenever the pattern returns.

---

## Challenge 5 (continued) — Turn the Recovery Runbook into a Reusable Skill

### Situation update

Investigation is reusable now; recovery should be too. The crew-scheduling
query-path recovery you performed in Challenge 4 is a well-defined, sanctioned
sequence — precisely the kind of repeatable recovery worth encoding as a skill so
that the next occurrence is handled consistently and quickly, without
re-deriving the steps under pressure.

### Your role

You are a reliability automation engineer, turning a proven recovery into a
reusable, governed skill.

### Mission

Encode one of the recovery procedures you performed — the crew pool relief is the
natural choice — as a reusable skill, then confirm it loads and can be applied so
the pattern is handled the same way every time.

### Business impact

Encoded recoveries reduce time-to-restore and remove human variance from a
sanctioned procedure, while still respecting approval. Consistency here directly
protects the departure schedule when the pattern recurs.

### Evidence available

- The skills surface in the agent.
- Your Challenge 7 recovery steps and the database runbook guardrails.
- The behavior of skills loading automatically.

### Constraints and guardrails

- The skill must encode the **sanctioned** recovery (repair the query path),
  never a destructive action.
- Keep any write step under approval; the skill should not silently perform
  ungoverned changes.
- Respect the platform limit on concurrently active skills.

### Success criteria

- A reusable skill captures the sanctioned recovery.
- The skill loads and can be invoked/applied.
- The encoded procedure matches the runbook guardrails.
- You can explain how a skill differs from the specialist subagent.

### Challenge tasks

1. Translate the crew query-path steps into a skill, keeping the guardrails
   (fix the saturated layer, never delete the database) intact.
2. Confirm the skill loads and can be applied to the relevant scenario.
3. Contrast the skill (auto-loaded, procedural) with the specialist subagent
   (explicitly invoked, investigative).

### Questions to answer

- Which recovery is the best candidate to encode, and why?
- How do you ensure the skill keeps the sanctioned guardrails?
- How does an auto-loading skill differ from an invoked subagent?
- How would this skill behave in the final incident?

### Useful documentation

- [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)
  — authoring a reusable skill and how skills load.
- [Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks)
  — triggering behavior around events, if you extend the skill.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Reuse the exact steps from Challenge 4's recovery as the skill's backbone.
</details>

<details><summary>Hint 2 — keep it safe</summary>

Bake the guardrails in: repair the query path, never scale around it, and never
delete or restart the database.
</details>

<details><summary>Hint 3 — skill vs subagent</summary>

Skills load automatically and encode procedure; subagents are invoked and
investigate. You want both in the final incident.
</details>

<details><summary>Answer sheet</summary>

**Build.** Encode the crew query-path recovery as a skill with guardrails intact.

**Use.** Confirm it loads and can be applied.

**Verification.** The skill matches the sanctioned procedure; you can explain
skill vs subagent.

**Reflection.** Recovery is now as reusable as investigation.

`check-challenge.ps1 5` confirms the skill. Exact authoring steps are in
[CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 5.
</details>

### What you unlocked

- **Agent capability:** reusable skill creation.
- **Operational capability:** consistent, governed recovery.
- **Artifact:** an encoded recovery skill.
- **Next:** with more agents, subagents, and skills in play, leadership wants to
  scale this without runaway consumption.

### Shift handover

You now have a specialist that investigates and a skill that recovers. Leadership
loves the momentum — and immediately asks the FinOps question: if we roll Azure
SRE Agent out across more operational domains, how do we keep consumption
predictable without blunting reliability?

---

## Challenge 6 — Keep the Agent Effective Without Wasting AAUs

### Situation update

Aetherion's leadership wants to expand Azure SRE Agent beyond this one operations
domain to cover more of the platform. Before they approve that, they want a
consumption model they can trust: predictable Azure Agent Unit (AAU) usage, clear
ownership boundaries, and no waste — without weakening investigation quality or
reliability. The mandate is explicitly **not** "make it as cheap as possible." It
is "make it cost-aware while preserving reliability, security, ownership, and
investigation quality."

This challenge is about the consumption and governance of Azure SRE Agent itself —
not general Azure infrastructure cost optimization.

### Your role

You are a FinOps-aware SRE, designing a sustainable operating model for the agent.

### Mission

Review how the agent consumes resources and design a cost-aware operating model
that reduces unnecessary consumption while preserving reliability, security,
ownership boundaries, and investigation quality.

### Business impact

An unmanaged rollout can multiply agents, alerts, and scheduled work until
consumption is unpredictable — stalling the very expansion leadership wants. A
sound operating model lets the platform scale coverage responsibly.

### Evidence available

- The agent's own consumption/usage data by thread type and purpose (inspect what
  is actually available in your environment).
- The set of agents, subagents, skills, response plans, and scheduled tasks you
  and others have created.
- The [Pricing & billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
  documentation.

### Constraints and guardrails

- Optimize the **agent's** consumption, not unrelated Azure infrastructure.
- Do not invent AAU rates, prices, or savings figures — use only values present in
  the official documentation or your environment; otherwise keep it qualitative
  and inspect the real consumption data.
- Do not claim that stopping an agent ends all billing.
- Preserve ownership boundaries, RBAC, isolation, and investigation quality —
  cheaper must not mean less reliable.

### Success criteria

- You have reviewed the available consumption data rather than guessing.
- You can identify concrete reductions (for example, consolidating compatible
  workloads, deleting unused pilot agents, right-sizing model choice, trimming
  noisy response plans or over-frequent scheduled tasks).
- Your model preserves ownership, RBAC, isolation, and investigation quality.
- You can justify each change as cost-aware, not merely cheapest.

### Challenge tasks

1. Inspect the agent's consumption by thread type and operational purpose to see
   where AAUs actually go before proposing changes.
2. Evaluate the estate against the cost levers — too many agents, consolidatable
   workloads, unused pilots, model fit, noisy response plans, over-frequent
   schedules, weak grounding, allocation limits — and decide which apply.
3. Produce a cost-aware operating model that balances cost, isolation, RBAC,
   ownership, and operational risk.

### Questions to answer

- Where is consumption actually going, by thread type and purpose?
- Are there too many agents, or workloads that could consolidate under fewer?
- Should any unused pilot agents be deleted?
- Does the selected model match the workload?
- Are response plans processing unnecessary alerts, or schedules running too
  often?
- Could better knowledge/skills grounding reduce repeated investigation?
- Are monthly allocation limits set appropriately?
- How does your model preserve reliability, security, and ownership while cutting
  waste?

### Useful documentation

- [Pricing & billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
  — how Azure SRE Agent consumption and billing work (use these values, do not
  invent your own).
- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — capabilities to weigh when consolidating or scoping agents.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Look at real consumption data first, broken down by thread type and purpose.
Optimize what you can measure.
</details>

<details><summary>Hint 2 — the levers</summary>

Consolidation, deleting unused pilots, model fit, alert/response-plan noise, and
schedule frequency are usually the biggest levers.
</details>

<details><summary>Hint 3 — the goal</summary>

The target is a *balanced* model: cost-aware while preserving isolation, RBAC,
ownership, and investigation quality — not the cheapest possible setup.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Review consumption by thread type/purpose and inventory the
agents, subagents, skills, response plans, and schedules in play.

**Design.** Propose consolidations, remove unused pilots, right-size model choice,
trim noisy alerts/response plans and over-frequent schedules, and strengthen
grounding to reduce repeated investigation — while keeping ownership, RBAC, and
isolation intact.

**Verification.** A written, cost-aware operating model that is defensibly
balanced.

**Reflection.** The platform can now expand agent coverage responsibly.

Discussion prompts are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 6.
</details>

### What you unlocked

- **Agent capability:** consumption awareness and governance.
- **Operational capability:** a sustainable, cost-aware operating model.
- **Artifact:** a documented agent operating model.
- **Next:** with a governed, cost-aware model in place, it is time to let the
  agent handle a bounded incident on its own.

### Shift handover

Leadership has its operating model and the expansion is greenlit — and they want
proof the agent can act without a human in the loop for routine problems. A small,
well-understood fault on a low-risk service is the perfect first test before the
peak-departure rush.

---

## Challenge 6 (continued) — Cleared for Autonomous Recovery

### Situation update

You have taught the agent, given it a specialist and a skill, and agreed a
governed operating model. So far every write has waited for your approval. Now a
minor issue appears: the **baggage** service is returning intermittent errors to a
slice of traffic. Bags are still moving, no flight is grounded, and the fix is one
you have already seen — a small blast radius and a well-understood remedy. That
combination is exactly when it is safe to let the agent run in **Autonomous** mode
and recover end-to-end while you supervise the outcome rather than each step.

This is the graduation from *approval* to *bounded autonomy* — the capability
customers always ask about: "can it just do this itself?"

### Your role

You are the SRE supervising the agent's first autonomous recovery on a low-risk
service.

### Mission

Give the agent a **bounded** autonomous posture for the baggage service and let it
detect, decide, and remediate the incident on its own — without per-action
approval — then verify it recovered correctly. You watch; you do not fix it by
hand. Finally, **arm a Sev1 major-incident response plan** so the agent triggers
itself the next time the platform breaks — in place before the final incident.

### Business impact

Baggage errors slow bag drop and irritate passengers, but they do not stop
aircraft moving — a low-consequence place to prove autonomy safely. If the agent
can shrink mean-time-to-recovery for routine faults without a human in the loop,
the team reclaims attention for the incidents that genuinely need judgment.

### Evidence available

- The Operations Center baggage tile and error indicators.
- Application Insights exceptions/failures for `baggage`.
- The agent's live activity and action plan as it works.
- AKS pod status and rollout history for `baggage`.

### Constraints and guardrails

- Keep autonomy **bounded**: scope the agent's write ability to what this recovery
  needs, and keep the database and other tiers off-limits.
- You remain the reviewer — you can stop the agent at any point.
- Do **not** remediate manually; the objective is to observe the agent's
  detect → decide → act loop end to end.
- Keep the action reversible and within the runbooks.

### Success criteria

- The agent detects the baggage errors on its own and proposes a sanctioned fix.
- The agent executes the fix **autonomously** (no per-action approval from you).
- The baggage service returns to healthy and the fault is cleared.
- You can explain what the agent did and why it was safe to automate.
- A **Sev1** response plan is active on the agent, bound to the
  `aetherion-major-incident` alert and ready to auto-trigger in Challenge 7.
- `check-challenge.ps1 6` passes.

### Challenge tasks

1. Confirm the baggage symptom in the Operations Center and telemetry so you know
   what "recovered" will look like.
2. Grant a **bounded** autonomous posture — a narrowly scoped write role plus
   **Autonomous** run mode — sufficient for this service's recovery and no more.
3. Let the agent run without intervening; watch it identify the fault, decide on a
   remedy, and apply it.
4. Verify the service is healthy and review the agent's action log to confirm it
   stayed within guardrails.
5. **Arm a major-incident response plan:** create a response plan on the agent
   filtered to **Severity = Sev1** and bound to the pre-provisioned
   `aetherion-major-incident` alert, so the next major incident auto-triggers an
   investigation. Do this now — it must be in place before Challenge 7.

### Questions to answer

- What makes this incident safe to automate when the check-in incident was not?
- Which guardrails keep the autonomy bounded rather than open-ended?
- How would you detect if the agent had taken the wrong action?
- What would you require before granting autonomy on a Tier 0 service?

### Useful documentation

- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — enabling Autonomous mode and scoping the write role that bounds it.
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
  — keeping autonomous action safe and reversible.
- [Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks)
  — how autonomous responses can be triggered and constrained.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Confirm the symptom first. You cannot judge an autonomous recovery if you do not
know what healthy looks like for baggage.
</details>

<details><summary>Hint 2 — bound the autonomy</summary>

Autonomy is safe because it is *scoped*. Give the agent only the write permission
this one recovery needs, then switch it to Autonomous — not broad access.
</details>

<details><summary>Hint 3 — resist helping</summary>

The point is to watch the agent work. If you fix baggage by hand, you have proven
nothing about autonomy. Let it run and verify afterward.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Confirm baggage is returning errors (Ops Center tile + App
Insights failures).

**Setup.** Scope a narrow write role for the agent's identity, switch the run mode
to Autonomous for this bounded recovery, and let it act.

**Recovery.** The agent detects the fault and applies a sanctioned, reversible
remedy (clear the fault / restart / roll back) with no per-action approval.

**Verification.** Baggage healthy and the fault cleared; the action log shows it
stayed within guardrails; `check-challenge.ps1 6` passes.

**Reflection.** Bounded autonomy is fast *and* safe when scope, reversibility, and
supervision are in place — and that judgment is what changes as tier and blast
radius grow.

Exact steps are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 6.
</details>

### What you unlocked

- **Agent capability:** bounded autonomous detection and recovery.
- **Operational capability:** faster recovery for routine faults, human attention
  reserved for the hard ones.
- **Artifact:** a supervised autonomous-recovery run and its action log, plus an
  armed **Sev1** major-incident response plan bound to `aetherion-major-incident`.
- **Next:** you have earned enough trust to rely on the agent when everything
  breaks at once.

### Shift handover

The agent cleared the baggage incident on its own while you supervised. Confidence
is high — and then, minutes before the peak departure bank, the wall lights up red
across multiple services at once. This is the shift's defining moment.

---

## Challenge 7 — Final Incident: Restore Global Check-In Before Peak Departure

### Situation update

Minutes before peak departures, several services fail together under a passenger
surge. The flight board is dark again, crew scheduling is failing, check-in has
slowed to a crawl, and the API front door is turning legitimate partner and mobile
traffic away with errors. The risk gauge is pinned high. This is a major incident,
and the clock is the departure schedule.

The incident unfolded fast — this is how customers experienced it:

| Time | Event |
|------|-------|
| 18:07 | A change rolls out to flight-ops |
| 18:12 | Check-in / booking latency begins to climb |
| 18:14 | Crew scheduling starts timing out under load |
| 18:17 | The live flight board goes dark for all stations |
| 18:21 | The API front door starts failing partner traffic |
| 18:25 | Major incident declared — you are incident commander |

Everything you have assembled today is now in play: the baseline to measure
against, the specialist to triage AKS, the knowledge to choose sanctioned fixes,
the skill to recover the crew pool, change awareness to spot what shipped, bounded
autonomy for the low-risk pieces, the armed **Sev1** response plan that
auto-triggers the agent, and the governance to act safely at speed. You
must triage by business impact, recover in the right order, and verify each fix.

### Your role

You are the incident commander for a platform-wide, Tier 0 major incident.

### Mission

Bring Aetherion AirOps back to full health before peak departure: triage all
issues, prioritize by business tier, remediate each within the runbook guardrails
using approved or explicitly bounded actions, and verify recovery service by
service.

### Business impact

Simultaneous failure of the flight board, crew scheduling, check-in, and the API
front door during a departure peak is a worst-case operational scenario:
grounded situational awareness, unconfirmed crews, stranded passengers, and
rejected partner traffic all at once. Ordered, verified recovery is what prevents
a cascade of delays and cancellations.

### Evidence available

- The Operations Center overview and per-service tiles.
- Application Insights and Grafana for each affected service.
- AKS pod status, events, and rollout history; your AKS specialist subagent.
- Azure Activity Log and GitHub change history.
- APIM policy and the direct-vs-APIM comparison.
- Your knowledge base and recovery skill.

### Constraints and guardrails

- Prioritize by business tier; restore situational awareness and legal-to-fly
  capability first.
- Every remediation stays within the runbooks: scale, never delete the database;
  reversible rollbacks; treat APIM policy changes as customer-facing.
- Use approval or explicitly bounded automation — no ungoverned, unbounded
  changes.
- Verify each service against health signals before moving on.
- Preserve the evidence you will brief leadership with.

### Success criteria

- All failing services are identified and triaged by priority.
- The flight board, crew scheduling, and check-in are all restored with
  sanctioned, reversible actions.
- The API front door serves legitimate traffic again.
- Every fix is verified from telemetry/health before closing it.
- The platform returns to healthy and `check-challenge.ps1 7` passes.

### Challenge tasks

1. Take stock of the whole board and order the work by business impact rather than
   by whichever alert is loudest.
2. Delegate AKS triage to your specialist and apply sanctioned recoveries —
   reuse your skill for the crew pool — while keeping actions governed.
3. Localize the front-door problem with the direct-vs-APIM comparison and treat
   the policy change as customer-facing.
4. Verify each service back to health, then confirm the whole platform is green.

> **Before you start:** confirm the **Sev1** response plan you armed in Challenge 6
> is active on the agent (bound to `aetherion-major-incident`). It should trigger
> the investigation on its own within a couple of minutes of the incident firing.
> If you skipped it, create it now — before you run the start command.

### Questions to answer

- What is the symptom, and what is the root cause, for each failing service?
- What are the contributing factors versus the primary causes?
- In what order should you remediate, and why that order?
- What is the immediate mitigation versus the permanent corrective action for
  each?
- What evidence proves each service has recovered?
- What risk remains after recovery?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — coordinating a multi-service investigation and recovery.
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
  — acting quickly but within governance during a major incident.
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
  — keeping bounded automation safe under pressure.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Do not fix the first red tile you see. Read the whole board and order by business
tier — situational awareness and legal-to-fly first.
</details>

<details><summary>Hint 2 — reuse what you built</summary>

Delegate AKS triage to your specialist and apply your crew-pool skill. You have
solved every one of these failure classes already.
</details>

<details><summary>Hint 3 — the front door</summary>

If the backend is healthy directly but clients still fail, the problem is at the
API front door, not the services.
</details>

<details><summary>Answer sheet</summary>

**Investigation.** Enumerate failing services; use the specialist for AKS and the
direct-vs-APIM check for the front door.

**Root-cause analysis.** Flight board in a failed state (change-related); crew pool
saturated; check-in throttled against a reduced CPU limit under surge; APIM failing legitimate
traffic.

**Remediation (ordered by tier).** Restore the flight board (reversible), relieve
the crew pool (skill/scale, never delete the DB), clear check-in latency and let
the HPA absorb load, and relax the customer-facing APIM policy under approval.

**Verification.** Each service back to green and APIM serving 200s; platform
healthy; `check-challenge.ps1 7` passes.

**Reflection.** Separate symptom, root cause, contributing factors, immediate
mitigation, and permanent corrective action for the write-up.

Exact prompts and commands are in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 7.
</details>

### What you unlocked

- **Agent capability:** end-to-end, governed, multi-fault incident response.
- **Operational capability:** tier-based triage and verified recovery at scale.
- **Artifact:** a fully recovered platform and a complete evidence trail.
- **Next:** the incident is technically closed — leadership needs it closed
  formally.

### Shift handover

The board is green again and departures are protected. The operations director is
already asking for a briefing: what happened, what it cost, how you recovered, and
whether it can happen again.

---

## Challenge 8 — Boarding Resumes: Brief Airline Leadership

### Situation update

The platform is stable and the peak departure bank is away safely. A major
incident is not closed when the tiles go green — it is closed when leadership
understands it and the team has captured what to do differently. Your final task
is to turn the shift's evidence into two artifacts: an engineering RCA handover
for the next on-call and a concise leadership briefing for executives.

### Your role

You are the incident commander closing out a Tier 0 major incident.

### Mission

Produce a management-ready incident summary and an engineering RCA handover that clearly
separate symptom, root cause, contributing factors, immediate mitigation,
permanent corrective action, evidence of recovery, and remaining risk.

### Business impact

A clear briefing preserves leadership's trust, informs prevention investment, and
turns a stressful shift into durable organizational learning. A vague one wastes
the incident.

### Evidence available

- The full evidence trail you preserved across the shift.
- The agent's action plans and summaries from the incidents.
- The baseline, telemetry, and change history you referenced.

### Constraints and guardrails

- Ground every statement in evidence you actually captured.
- Do not overstate autonomous capability or claim unrealistic prevention.
- Keep the leadership briefing concise; keep the engineering RCA handover precise.
- Distinguish what was mitigated from what is permanently fixed.

### Success criteria

- The platform is healthy at close.
- The leadership briefing covers impact, root cause, recovery, cost/risk, and
  lessons learned.
- The engineering RCA handover captures actions taken, verification, remaining
  risk, and change-correlation evidence (Activity Log + GitHub).
- Symptom, root cause, contributing factors, immediate mitigation, and permanent
  corrective action are clearly separated.
- `check-challenge.ps1 8` passes.

### Challenge tasks

1. Assemble the shift's evidence into a single narrative per incident so the story
   is defensible.
2. Write the leadership briefing — short, impact-first, non-technical where
   possible — for the operations director.
3. Write the engineering RCA / technical handover — precise actions,
  verification, open risks, and change-correlation evidence (Activity Log +
  GitHub commit/PR references) — for the next on-call engineer.

### Questions to answer

- What was the business impact, in operational terms?
- What was the root cause of each incident, versus the contributing factors?
- What was mitigated immediately, and what is the permanent corrective action?
- What evidence proves the platform recovered?
- What risk remains, and what should be done to prevent recurrence?

### Useful documentation

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
  — using the agent's summaries as input to your write-up.
- [Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)
  — feeding lessons learned back so the agent remembers them next time.

### Hints

<details><summary>Hint 1 — where to begin</summary>

Start from the evidence you preserved, not from memory. Let the agent's action
plans jog the timeline.
</details>

<details><summary>Hint 2 — two audiences</summary>

Leadership wants impact and outcome; the next on-call wants exact actions,
root-cause evidence, and open risks. Write both, not one blended document.
</details>

<details><summary>Hint 3 — close the loop</summary>

Feed the lessons learned back into the agent's knowledge so recurrence is handled
faster next time.
</details>

<details><summary>Answer sheet</summary>

**Assemble.** One evidenced narrative per incident from the trail you kept.

**Leadership briefing.** Impact, root cause, recovery, cost/risk, lessons — concise
and outcome-first.

**Engineering RCA handover.** Actions taken, verification, remaining risk, and
Activity Log + GitHub change references — precise.

**Verification.** Platform healthy and both artifacts produced;
`check-challenge.ps1 8` passes.

**Reflection.** The incident is now formally closed and the team is smarter for it.

A briefing template is in [CHEAT-SHEET.md](CHEAT-SHEET.md) under Challenge 8.
</details>

### What you unlocked

- **Agent capability:** incident summarization and knowledge feedback.
- **Operational capability:** leadership-ready closure and durable learning.
- **Artifact:** an executive leadership briefing and an engineering RCA handover.
- **Next:** the shift is complete — tear down the environment when you are done.

### Shift handover

Your shift ends with the platform green, leadership briefed, and the next on-call
set up to succeed. Aetherion AirOps kept flying because you investigated from
evidence, acted under governance, and verified every recovery.

---

## Wrap-up & cleanup

- Reset any lingering faults between runs: `./scripts/reset-environment.ps1`
- Tear the whole environment down when finished: `./scripts/99-teardown.ps1`

The exact clicks, prompts, values, and commands for every challenge live in
[CHEAT-SHEET.md](CHEAT-SHEET.md). Facilitators running a guided session can inject
incidents manually with `./scripts/inject-failure.ps1` instead of
`start-challenge.ps1`.

---

## Appendix A — Azure SRE Agent fundamentals

Read this once when convenient. The two controls from *Azure SRE Agent in one
minute* are the core; everything below rounds out the picture.

**Two independent controls.**

1. **Permissions (Azure RBAC):** what the agent's identity is *allowed* to do (for
   example Reader vs a narrower write role). When it lacks permission it can fall
   back to **on-behalf-of (OBO)** and ask you to approve using *your* credentials.
2. **Run mode:** *how* it acts — **Review** (proposes, waits for approval) vs
   **Autonomous** (acts within its permissions and guardrails).

**Other essentials.**

- **Skills load automatically**; **custom subagents are invoked explicitly** (for
  example with `/agent`). Skills are capped at **5 concurrent active** at a time.
- Only a user with the **Azure SRE Agent Administrator** role can approve proposed
  actions.
- The **knowledge base** accepts Markdown/text files (this repo's `knowledge/`),
  which is how you ground the agent in Aetherion's runbooks and standards.
- Creating an agent also provisions its **own** Application Insights, Log
  Analytics, and managed identity — separate from the application's telemetry.

**Documentation you will return to all day:**
[Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) ·
[Create and set up](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up) ·
[Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup) ·
[Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions) ·
[Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview) ·
[Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard) ·
[Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents) ·
[Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills) ·
[Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks) ·
[Pricing & billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
