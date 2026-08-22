# Challenge 7 · Final Incident: Restore Global Check-In Before Peak Departure

!!! abstract "Challenge 07 of 08 · Act V: Major Incident"
    **Run mode:** Review + bounded automation · **Governance:** you decide what is approved and what is automated

    **Stage:** Foundation → Operations → Engineering → Autonomous → **Major Incident**

**Situation.** Minutes before peak departures, several services fail together under
a passenger surge: the flight board is dark, crew scheduling is timing out, check-in
has slowed to a crawl, and the API front door is failing legitimate partner and
mobile traffic. The risk gauge is pinned. Everything you built today is now in play.

**You are not first on scene.** The Sev1 plan you armed in Challenge 6 matched the
alert before anyone paged you, and the agent has been working the incident
unattended. Your first job is not to fix something. It is to find out what has
already been changed in your absence.

| Time | Event |
|------|-------|
| 18:07 | A change rolls out to flight-ops |
| 18:12 | Check-in / booking latency begins to climb |
| 18:14 | Crew scheduling starts timing out under load |
| 18:17 | The live flight board goes dark for all stations |
| 18:21 | The API front door starts failing partner traffic |
| 18:23 | `aetherion-major-incident` fires at **Sev1** and auto-triggers the agent |
| 18:25 | Major incident declared. You are incident commander |
| 18:26 | The agent is already acting on its own in a thread it opened itself |

**Mission.** Take handover from the agent, then bring Aetherion AirOps back to full
health before peak departure: verify what it changed without you, triage the rest by
business tier, remediate within the runbook guardrails, and verify recovery service
by service.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-clipboard-account-outline: **Take handover**: audit what an autonomous agent changed while you were away
- :material-clipboard-list-outline: **Triage by impact**: order by business tier, not the loudest alert
- :material-history: **Agent memory**: recall the earlier RCA to resolve faster
- :material-account-group-outline: **Delegate & reuse**: your specialist subagent and crew recovery skill
- :material-check-all: **Verify each fix**: service by service, back to green

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 7   # open the incident
    ```

    Four faults land at once and the board takes two or three minutes to reflect
    all of them. Don't start triaging from a half-drawn picture.

### Tasks

1. **Take handover from the agent.** Find the thread the Sev1 alert opened by itself, read what the agent has already changed unattended, and verify it independently before you trust it.
2. **Read the whole board.** Order the remaining work by business impact (situational awareness and legal-to-fly first), not the loudest alert.
3. **Check the agent's memory.** Ask whether a similar incident has happened and let session insights surface the earlier RCA.
4. **Delegate and recover.** Hand AKS triage to your specialist subagent and reuse your crew recovery skill, keeping every action governed.
5. **Localize the front door.** Use the direct-vs-APIM comparison and treat the policy change as customer-facing.
6. **Verify every service.** Confirm each fix from telemetry, then the whole platform back to green.

!!! note "Why Sev1?"
    The environment pre-provisions a fixed **Sev1** Azure Monitor alert
    (`aetherion-major-incident`, on Application Insights failed requests). A response
    plan matches incoming alerts **by severity**, so your filter must be `Sev1` to
    catch it; a broader filter fires on everything, a mismatched one catches nothing.

    **This one is graded.** `check-challenge.ps1 7` marks the platform's end state
    *and* confirms a Sev1 major-incident alert actually fired since you started the
    challenge. Driving the whole incident by hand is not enough on its own.

![Challenge 7 storyboard: Sam, Aria and Elena restore global check-in before peak departure](../assets/storyboard/img-challenge-7.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    You picked this incident up before I did. List every action you have already
    taken without my approval, and how I can verify each one. Then tell me what is
    still broken, and what you recommend I deal with first.

The second half is the part you own. It will give you an order; your job is to
decide whether it's the right one for an airline at peak departure.

### Success criteria

- You can state exactly what the agent changed without your approval, and you verified it from the cluster rather than from its summary.
- All remaining failing services are triaged by priority and restored with sanctioned, reversible actions.
- The API front door serves legitimate traffic again, and every fix is verified from telemetry/health before closing.
- The platform is healthy and `check-challenge.ps1 7` passes.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 7
    ```

### Hints

<details markdown="1"><summary>Hint: triage, don't firefight</summary>

Don't fix the first red tile you see; read the whole board and order by business
tier. You've solved every one of these failure classes already: delegate AKS triage
to your specialist and apply your crew recovery skill.
</details>

<details markdown="1"><summary>Hint: is it the service, or the front door?</summary>

If the backend is healthy when you hit it directly but clients still fail, the
problem is at the API front door, not the services. Treat the policy change as
customer-facing.

Expect the board to get *worse* once the front door is fixed: with traffic flowing
again, the degradations further back become visible. That is normal in a layered
incident. Restoring the edge doesn't create new faults, it reveals the ones the
outage was masking.
</details>

<details markdown="1"><summary>Hint: how an experienced incident commander would have scoped it</summary>

If the agent's account is scattered, this is how someone who has run a major
incident would ask for it:

> Read the whole Aetherion board and give me an incident-command triage: list every
> service still failing, order remediation by business tier (situational awareness
> and legal-to-fly first), and for each name the sanctioned, reversible fix. Have we
> seen a similar crew-scheduling / check-in incident before? Pull the earlier RCA
> from session memory.

Two things in there are doing the work: **order by business tier**, which stops you
fixing whatever is loudest, and **pull the earlier RCA from memory**, which is the
difference between solving crew scheduling for the first time and the second.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first, and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Take handover from the agent"
        The agent started before you did. Treat this exactly like taking handover
        from a colleague who has been on the incident for ten minutes.

        **Find the thread it opened by itself.** In the agent's chat list, look for
        a thread whose title starts with `[Sev1] aetherion-major-incident`. You did
        not create it. The response plan did, off the alert.

        **Read what it already changed.** Ask it directly, in that thread:

        > You picked this incident up before I did. List every action you have
        > already taken without my approval, what each one changed, and how I can
        > verify it. Then list what you deliberately did not act on, and why.

        **Verify it yourself. Do not take its word for it.** The whole point of
        autonomy is that you audit the outcome, not the intention:

        ```powershell
        kubectl -n aetherion rollout history deployment/flight-ops
        kubectl -n aetherion get deploy flight-ops -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
        ```

        Expect it to have acted on **some** tiers and not others. It moves where the
        fix is unambiguous and reversible, and holds where the call is a judgement.
        Those held tiers are your work.

        !!! tip "If no thread was auto-created"
            The plan did not match. Open **Incidents → Triggers + response plans**
            and confirm your Sev1 plan shows **Status: On** and **Severity: Sev1**,
            that **Subagent name** reads *Set up* (none bound), and that no leftover
            **quickstart** plan is competing with it. Fix it, then re-run the start
            command so the alert fires again. You can still command the incident by
            hand, but the alert has to fire for this challenge to pass.

    ??? note "Task 2 · Read the whole board"
        - Open the Operations Center and list every failing service. Order remediation
          by business tier: situational awareness (flight board) and legal-to-fly
          (crew) first, not by whichever alert is loudest.

        !!! warning "The board cannot see your front door"
            The Operations Center polls each service **directly**, inside the
            cluster. It has no view of API Management. So the board can read fully
            green while every partner and mobile customer is getting a 500 at the
            edge, which is exactly what happens in this incident.

            Validated: an agent told to "read the whole board" recovered all four
            in-cluster faults, declared the incident stable, and never mentioned the
            front door once. It was not wrong about the board. The board was
            incomplete.

            Treat the internal board and the customer-facing path as two separate
            questions, and always ask the second one. That is Task 5.

    ??? note "Task 3 · Check the agent's memory"
        Ask it directly, in the same thread as the investigation:

        > Have you investigated a crew-scheduling or check-in slowdown on this
        > platform before? Recall what the root cause was and which fix worked.

        If you saved a hypothesis in Challenge 2 or grounded the runbooks in
        Challenge 4, session insights should surface the earlier RCA and the fix.
        That is the point of the exercise: the second incident should cost less
        than the first.

    ??? note "Task 4 · Delegate and recover"
        Name both the subagent and the skill explicitly. Neither fires on its own.

        For the AKS tier:

        > Delegate this to your `aks-triage` subagent: which workloads in the
        > `aetherion` namespace are unhealthy, and why?

        Expect it to investigate and then **hand back rather than fix**. You scoped
        it without `RunKubectlWriteCommand` in Challenge 5, so it physically cannot
        change the cluster. It reports; you and the main agent act on it. That split
        is deliberate, and under incident pressure it is worth noticing that you do
        not have to trust a prompt to keep it in its lane.

        For the crew tier:

        > Use the `crew-query-path-recovery` skill to restore crew scheduling.

        Crew is failing the same way it did in Challenge 4, so the skill carries.
        Asking the agent to "act as" a specialist does **not** invoke the subagent,
        it only adopts the persona.

        - Keep actions governed and follow the runbooks: fix the layer that is
          actually saturated, never delete the database.

        !!! tip "Time the crew tier specifically"
            Note the minutes from starting on crew scheduling to the point it is
            healthy again. This is the same failure class you worked cold in
            Challenge 2 and diagnosed in Challenge 4 — but now the agent has your
            runbooks, a skill written for exactly this, and a memory of the earlier
            incident.

            Compare it with the number you wrote down in Challenge 2. Whatever the
            gap is, that is the finding you take to Challenge 8. If it is smaller
            than you expected, that is worth reporting honestly too.

    ??? note "Task 5 · Localize the front door"
        - Compare backend health **directly** (`http://<gateway-ip>/api/status`)
          against the same call **through APIM**. If direct returns 200 but APIM
          fails, the fault is the **edge policy**, not the service; treat the change
          as customer-facing.

        !!! note "Why it can fix this at all"
            Everywhere else today the agent has held write access to Kubernetes and
            nothing else. It can repair the front door because its identity also
            holds **API Management Service Contributor**, scoped to the API
            Management service alone rather than the resource group.

            Narrow enough to fix this, too narrow to touch anything else. That is
            what least privilege looks like when it is actually load-bearing: had it
            been scoped to the resource group, the same repair would have carried the
            authority to change every resource in the environment.

    ??? note "Task 6 · Verify every service"
        - Confirm each fix from telemetry / health before closing, then check the
          whole platform is green and `/api/flights` responds.

### Reference

- [Automate incident response](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response)
- [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans)
- [Review and approve mitigations](https://learn.microsoft.com/en-us/azure/sre-agent/execute-mitigations)

!!! success "Up next: brief airline leadership"
    The incident is technically closed; now leadership needs it closed formally.

    [Proceed to Challenge 8 · Leadership Briefing →](08-leadership-briefing.md){ .md-button .md-button--primary }

---
