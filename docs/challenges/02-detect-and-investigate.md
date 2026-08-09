# Challenge 2 — Detect and Investigate Without Touching Production

!!! abstract "Challenge 02 of 08 · Act II — Human-Guided Operations"
    **Agent mode:** Reader (read-only) · **Permissions:** Reader · **Estimated time:** 20–30 min

    **Stage:** Foundation → **Operations** → Engineering → Autonomous → Major Incident

**Situation.** Passengers are reporting long check-in waits and the **booking /
check-in** tile is drifting from green toward amber — just as traffic climbs toward a
departure peak. Is check-in broken, or simply busy? A change on the passenger path
mid-surge is what turns a slowdown into an outage. This incident stays **open** into
Challenge 3 — here you detect and investigate, you do not fix.

**Mission.** Confirm the check-in degradation from live signals and form a
root-cause hypothesis backed by at least two independent signals — without changing
anything in production.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-magnify-scan: **Confirm the symptom** — tell a real regression apart from load
- :material-chart-line: **Correlate signals** — latency against CPU, replicas and request load
- :material-shield-check-outline: **Zero production risk** — a rigorous read-only investigation
- :material-lightbulb-on-outline: **Defensible hypothesis** — the evidence that speeds the approved fix

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 2   # open the incident
    ```

### Tasks

1. **Confirm the symptom** — compare current check-in latency to your Challenge 1 baseline; trust the delta, not the feeling.
2. **Correlate read-only** — have the agent correlate `booking` request duration with CPU, replica count and request load.
3. **Test the capacity theory** — if replicas scaled but latency stayed high while CPU isn't saturated, load alone doesn't explain it.
4. **Record the hypothesis** — write the root cause, the ≥2 signals behind it, and the least-disruptive recovery you'd propose (don't perform it).

!!! question "Stuck? Full walkthrough available"
    Give each task a genuine attempt before reaching for help — working it out
    yourself is where the learning sticks. Only if you get truly stuck, the
    [Azure portal walkthrough](../getting-started/portal-walkthrough.md) has the
    exact click-by-click for every step.

![Challenge 2 storyboard — Sam and Aria detect and investigate the incident read-only](../assets/storyboard/img-challenge-2.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Analyze the check-in / booking path read-only. Correlate `booking` request
    duration with CPU, replica count, and request load over the last 30 minutes.
    Is the latency explained by capacity, or is there an added delay independent of
    load? Give a root-cause hypothesis with supporting evidence — and change nothing.

!!! tip "Optional — feed the agent a HAR trace or screenshot"
    If a partner reports the failure from their side, capture a **HAR trace**
    (browser DevTools → Network → *Save all as HAR*) or a screenshot of the failing
    call and **upload it in the agent chat** — the agent parses HAR and image files
    directly and folds client-side timing into its investigation.

### Success criteria

- You've confirmed the degradation and can name the affected service and user-facing path.
- You can name the most likely source, backed by at least two independent signals, and separate the load-driven latency from the added delay.
- You've made no change to production.

!!! success "Verify your work"

    Run this when you're done — it grades the real end state and unlocks the next challenge:

    ```powershell
    ./scripts/check-challenge.ps1 2
    ```

### Hints

<details markdown="1"><summary>Hint</summary>

Compare `booking` latency now against your recorded baseline — trust the delta, not
the feeling. Correlate request duration with CPU and replicas over the same window,
not latency alone. If the autoscaler added replicas and CPU isn't saturated yet
latency stays high, the delay is being added independently of load — think about
what adds a roughly constant delay per request. Detection is done when you can
describe the symptom precisely and defend a hypothesis, not when it's fixed.
</details>

### Reference

- [Azure SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — controlled recovery under approval"
    With a defensible hypothesis, you're ready to recover check-in under approval — and then the flight board goes dark.

    [Proceed to Challenge 3 · Controlled Recovery →](03-controlled-recovery.md){ .md-button .md-button--primary }

---
