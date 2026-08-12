# Challenge 7 — Final Incident: Restore Global Check-In Before Peak Departure

!!! abstract "Challenge 07 of 08 · Act V — Major Incident"
    **Run mode:** Review + bounded automation · **Access:** scoped write

    **Stage:** Foundation → Operations → Engineering → Autonomous → **Major Incident**

**Situation.** Minutes before peak departures, several services fail together under
a passenger surge: the flight board is dark, crew scheduling is timing out, check-in
has slowed to a crawl, and the API front door is turning away legitimate partner and
mobile traffic. The risk gauge is pinned. Everything you built today is now in play.

| Time | Event |
|------|-------|
| 18:07 | A change rolls out to flight-ops |
| 18:12 | Check-in / booking latency begins to climb |
| 18:14 | Crew scheduling starts timing out under load |
| 18:17 | The live flight board goes dark for all stations |
| 18:21 | The API front door begins throttling partners |
| 18:25 | Major incident declared — you are incident commander |

**Mission.** Bring Aetherion AirOps back to full health before peak departure —
triage by business tier, remediate each fault within the runbook guardrails using
approved or bounded actions, and verify recovery service by service.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-clipboard-list-outline: **Triage by impact** — order by business tier, not the loudest alert
- :material-history: **Agent memory** — recall the earlier RCA to resolve faster
- :material-account-group-outline: **Delegate & reuse** — your specialist subagent and crew-pool skill
- :material-check-all: **Verify each fix** — service by service, back to green

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 7   # open the incident
    ```

### Tasks

1. **Confirm the Sev1 plan is live.** Check the response plan from Challenge 6 is active so the alert auto-triggers — if you skipped it, create it **before** you start.
2. **Read the whole board.** Order the work by business impact (situational awareness and legal-to-fly first), not the loudest alert.
3. **Check the agent's memory.** Ask whether a similar incident has happened and let session insights surface the earlier RCA.
4. **Delegate and recover.** Hand AKS triage to your specialist subagent and reuse your crew-pool skill, keeping every action governed.
5. **Localize the front door.** Use the direct-vs-APIM comparison and treat the policy change as customer-facing.
6. **Verify every service.** Confirm each fix from telemetry, then the whole platform back to green.

![Challenge 7 storyboard — Sam, Aria and Elena restore global check-in before peak departure](../assets/storyboard/img-challenge-7.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Read the whole Aetherion board and give me an incident-command triage: list every
    failing service, order remediation by business tier (situational awareness and
    legal-to-fly first), and for each name the sanctioned, reversible fix. Have we
    seen a similar crew-scheduling / check-in incident before — pull the earlier RCA
    from session memory.

!!! note "Why Sev1?"
    The environment pre-provisions a fixed **Sev1** Azure Monitor alert
    (`aetherion-major-incident`, on Application Insights failed requests). A response
    plan matches incoming alerts **by severity**, so your filter must be `Sev1` to
    catch it — a broader filter fires on everything, a mismatched one catches nothing.

### Success criteria

- All failing services are triaged by priority and restored with sanctioned, reversible actions.
- The API front door serves legitimate traffic again (no 429s), and every fix is verified from telemetry/health before closing.
- The platform is healthy and `check-challenge.ps1 7` passes.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 7
    ```

### Hints

<details markdown="1"><summary>Hint — triage, don't firefight</summary>

Don't fix the first red tile you see — read the whole board and order by business
tier. You've solved every one of these failure classes already: delegate AKS triage
to your specialist and apply your crew-pool skill.
</details>

<details markdown="1"><summary>Hint — is it the service, or the front door?</summary>

If the backend is healthy when you hit it directly but clients still fail, the
problem is at the API front door, not the services. Treat the policy change as
customer-facing.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first — and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Confirm the Sev1 plan is live"
        - Open **Builder → Incident response plans** and confirm your Sev1 plan (from
          Challenge 6) is **On** and filtered to match `aetherion-major-incident`.
        - If it's missing, create it **before** running the start command — otherwise
          the alert won't auto-trigger the investigation.

    ??? note "Task 2 · Read the whole board"
        - Open the Operations Center and list every failing service. Order remediation
          by business tier — situational awareness (flight board) and legal-to-fly
          (crew) first — not by whichever alert is loudest.

    ??? note "Task 3 · Check the agent's memory"
        - Ask the agent whether a similar crew-scheduling / check-in incident has
          happened before; let session insights surface the earlier RCA and the fix
          that worked.

    ??? note "Task 4 · Delegate and recover"
        - Invoke your **AKS specialist subagent** for pod / rollout triage, and apply
          your **crew-pool skill** for the sanctioned recovery.
        - Keep actions governed (approval or a scoped role) and follow the runbooks:
          scale to relieve pressure, never delete the database.

    ??? note "Task 5 · Localize the front door"
        - Compare backend health **directly** (`http://<gateway-ip>/api/status`)
          against the same call **through APIM**. If direct is 200 but APIM returns
          429, the fault is the **edge policy**, not the service — treat the change as
          customer-facing.

    ??? note "Task 6 · Verify every service"
        - Confirm each fix from telemetry / health before closing, then check the
          whole platform is green and `/api/flights` responds.

### Reference

- [Automate incident response](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response)
- [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans)
- [Review and approve mitigations](https://learn.microsoft.com/en-us/azure/sre-agent/execute-mitigations)

!!! success "Up next — brief airline leadership"
    The incident is technically closed — now leadership needs it closed formally.

    [Proceed to Challenge 8 · Leadership Briefing →](08-leadership-briefing.md){ .md-button .md-button--primary }

---
