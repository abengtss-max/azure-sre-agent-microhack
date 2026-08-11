# Challenge 7 — Final Incident: Restore Global Check-In Before Peak Departure

!!! abstract "Challenge 07 of 08 · Act V — Major Incident"
    **Agent mode:** Approved + bounded automation · **Permissions:** scoped write · **Estimated time:** 40–50 min

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

1. **Confirm the Sev1 plan is live** — check the response plan from Challenge 6 is active (bound to `aetherion-major-incident`) so the alert auto-triggers an investigation. If you skipped it, create it now, **before** running the start command.
2. **Read the whole board** — order the work by business impact (situational awareness and legal-to-fly first), not the loudest alert.
3. **Check the agent's memory** — ask whether a similar crew-scheduling / check-in incident has happened, and let session insights surface the earlier RCA and remediation.
4. **Delegate & recover** — hand AKS triage to your specialist subagent and apply sanctioned recoveries (reuse your crew-pool skill), keeping actions governed.
5. **Localize the front door** — use the direct-vs-APIM comparison; treat the policy change as customer-facing.
6. **Verify every service** — confirm each fix from telemetry, then the whole platform green.

!!! question "Stuck? Give each task a genuine attempt first"
    Working it out yourself is where the learning sticks. If you need the exact
    clicks, the [Azure portal walkthrough](../getting-started/portal-walkthrough.md)
    has a step for every action.

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

<details markdown="1"><summary>Hint</summary>

Don't fix the first red tile you see — read the whole board and order by business
tier. Delegate AKS triage to your specialist and apply your crew-pool skill;
you've solved every one of these failure classes already. If the backend is
healthy directly but clients still fail, the problem is at the API front door, not
the services.
</details>

### Reference

- [Azure SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — brief airline leadership"
    The incident is technically closed — now leadership needs it closed formally.

    [Proceed to Challenge 8 · Leadership Briefing →](08-leadership-briefing.md){ .md-button .md-button--primary }

---
