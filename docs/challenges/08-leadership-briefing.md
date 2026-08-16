# Challenge 8 · Boarding Resumes: Brief Airline Leadership

!!! abstract "Challenge 08 of 08 · Act V: Major Incident"
    **Run mode:** Review · **Access:** read-only summarization

    **Stage:** Foundation → Operations → Engineering → Autonomous → **Major Incident**

**Situation.** The platform is stable and the peak departure bank is away safely. A
major incident isn't closed when the tiles go green; it's closed when leadership
understands it and the team has captured what to do differently.

**Mission.** Turn the shift's evidence into two artifacts (a concise leadership
briefing and an engineering RCA handover) that cleanly separate symptom, root cause,
contributing factors, mitigation, permanent fix, recovery evidence and remaining
risk.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-file-document-outline: **Two audiences**: a leadership briefing and an engineering RCA
- :material-podium: **Impact-first**: what happened and what it cost, for executives
- :material-clipboard-text-clock-outline: **Precise handover**: actions, verification and open risks for the next on-call
- :material-file-chart-outline: **Boardroom-ready**: an auto-generated PDF with a timeline chart

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 8   # open / set up this challenge
    ```

    Challenge 8 injects no fault, so the platform stays green while you write.

### Tasks

1. **Assemble the evidence.** Build one defensible narrative per incident from what you preserved through the shift.
2. **Write the leadership briefing.** Short, impact-first, non-technical, for the operations director.
3. **Write the engineering RCA handover.** Precise actions, verification, open risks, and change evidence for the next on-call.
4. **Generate the executive PDF.** Have the agent render the briefing (with a timeline chart) via its Python sandbox.

![Challenge 8 storyboard: Sam and Elena brief airline leadership as boarding resumes](../assets/storyboard/img-challenge-8.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    From today's preserved evidence and action plans, draft two separate artifacts:
    (1) a concise, impact-first **leadership briefing** (business impact, root cause,
    recovery, cost/risk, lessons learned) and (2) an **engineering RCA handover**
    (actions taken, how each was verified, open risks, and change evidence: rollout
    history with its recorded change causes for the workload changes, and the Azure
    Activity Log for the API Management policy change). Then render the leadership
    briefing as a formatted **PDF** with an incident-timeline chart using your Python
    sandbox.

### Success criteria

- The platform is healthy at close.
- The leadership briefing covers impact, root cause, recovery, cost/risk, and lessons learned; the engineering RCA handover captures actions, verification, remaining risk, and change evidence from rollout history and the Activity Log.
- The agent produced a **downloadable PDF** of the leadership briefing (with a timeline chart) via its Python sandbox.
- Symptom, root cause, contributing factors, immediate mitigation, and permanent corrective action are clearly separated, and `check-challenge.ps1 8` passes.

!!! success "Verify your work"

    The platform health is graded; the briefing and RCA are yours to attest to. Run
    this when you're done to complete the hack:

    ```powershell
    ./scripts/check-challenge.ps1 8
    ```

### Hints

<details markdown="1"><summary>Hint: evidence, and two audiences</summary>

Start from the evidence you preserved, not memory; let the agent's action plans jog
the timeline. Write two documents, not one blended one: leadership wants impact and
outcome; the next on-call wants exact actions, root-cause evidence, and open risks.
</details>

<details markdown="1"><summary>Hint: close the loop</summary>

Feed the lessons learned back into the agent's knowledge / memory so a recurrence is
handled faster next time.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first, and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Assemble the evidence"
        - Pull the timeline together from what you preserved during the shift (agent
          threads, action logs, Activity Log, telemetry): one defensible narrative
          per incident, not from memory.

    ??? note "Task 2 · Write the leadership briefing"
        Paste this into the agent chat:

        > Write a briefing for the operations director about today's major
        > incident. Lead with business impact, not technology. Cover: what
        > passengers experienced and for how long, the root cause in plain
        > language, how we recovered, the cost and residual risk, and the lessons
        > we are taking forward. Keep it under one page and use no Kubernetes
        > jargon.

        Judge it the way the director would. If a sentence needs a platform
        engineer to translate it, send it back.

    ??? note "Task 3 · Write the engineering RCA handover"
        Paste this into the agent chat:

        > Write an engineering RCA handover for the next on-call. List every
        > action taken and how each one was verified, the remaining risk, and the
        > change-correlation evidence with exact sources. Be precise enough that
        > someone who was not here could audit it.

        - Be specific about where that evidence lives. The workload changes are in
          **rollout history** (`kubectl rollout history deploy/<svc> -n aetherion`)
          with the change cause recorded against each revision; the API Management
          policy change is in the **Azure Activity Log** as a
          `Set Product policy configuration` operation. In-cluster changes never
          reach the Activity Log, which is itself worth calling out as a gap in the
          handover.
        - If the agent reports that it found nothing, ask it to query the Activity
          Log at **subscription scope** rather than filtering by resource group. The
          API Management policy operation is not always attributed to the resource
          group, so a resource-group-scoped query can come back empty even though
          the events are there.

    ??? note "Task 4 · Generate the executive PDF"
        Paste this into the agent chat:

        > Render the leadership briefing as a formatted PDF, including an incident
        > timeline chart, using your Python sandbox. Give me a download link.

        The agent writes the file in its sandbox and returns a link. If the
        download fails, ask it to list the generated file and give you the link
        again, because the first link can expire.

### Reference

- [Track incident value](https://learn.microsoft.com/en-us/azure/sre-agent/track-incident-value)
- [Monitor agent usage](https://learn.microsoft.com/en-us/azure/sre-agent/monitor-agent-usage)
- [Memory and knowledge](https://learn.microsoft.com/en-us/azure/sre-agent/memory)

!!! success "🎉 MicroHack complete: you built an AI SRE teammate from scratch"
    Across eight challenges you onboarded, investigated, recovered, grounded,
    engineered, automated, and closed a Tier-0 major incident with the Azure SRE
    Agent.

    [Finish & wrap up →](finish.md){ .md-button .md-button--primary }

---
