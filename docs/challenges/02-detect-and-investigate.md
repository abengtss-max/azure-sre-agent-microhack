# Challenge 2 · Detect and Investigate Without Touching Production

!!! abstract "Challenge 02 of 08 · Act II: Human-Guided Operations"
    **Run mode:** Review · **Access:** read-only investigation

    **Stage:** Foundation → **Operations** → Engineering → Autonomous → Major Incident

**Situation:** Passengers are reporting long check-in waits and the **booking /
check-in** tile is drifting from green toward amber just as traffic climbs toward a
departure peak. Is check-in broken, or simply busy? A change on the passenger path
mid-surge is what turns a slowdown into an outage. This incident stays **open** into
Challenge 3, here you detect and investigate, you do not fix.

**Mission:** Confirm the check-in degradation from live signals and form a
root-cause hypothesis backed by at least two independent signals without changing
anything in production.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-magnify-scan: **Confirm the symptom**: Tell a real regression apart from load
- :material-chart-line: **Correlate signals**: Latency against CPU, replicas and request load
- :material-shield-check-outline: **Zero production risk**: A rigorous read-only investigation
- :material-lightbulb-on-outline: **Defensible hypothesis**: The evidence that speeds the approved fix

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 2   # open the incident
    ```

    Starting Challenge 2 injects the first incident, so your board moves from
    green to degraded within a minute or two.

### Tasks

1. **Confirm the symptom.** Compare check-in latency now to your Challenge 1 baseline and trust the measured delta.
2. **Correlate read-only.** Have the agent line up `booking` request duration against CPU, replicas, and request load.
3. **Rule out capacity.** Decide whether load alone explains the latency, or something was added on the path.
4. **Record your hypothesis.** Capture the root cause, the two signals behind it, and the recovery you'd propose (without performing it).

![Challenge 2 storyboard: Sam and Aria detect and investigate the incident read-only](../assets/storyboard/img-challenge-2.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Analyze the check-in / booking path read-only. Correlate `booking` request
    duration with CPU, replica count, and request load over the last 30 minutes, and
    check recent deployments and rollout history for changes in the same window.
    Give a root-cause hypothesis with supporting evidence, and change nothing.

!!! tip "Optional: feed the agent a HAR trace or screenshot"
    If a partner reports the failure from their side, capture a **HAR** (HTTP
    Archive) trace (browser DevTools → Network → *Save all as HAR*) or a screenshot
    of the failing call and **upload it in the agent chat**. The agent parses HAR and
    image files directly and folds client-side timing into its investigation.

### Success criteria

- You've confirmed the degradation and can name the affected service and user-facing path.
- You can name the most likely source, backed by at least two independent signals, and separate the load-driven latency from the added delay.
- You've made no change to production.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 2
    ```

### Hints

<details markdown="1"><summary>Hint: confirm and correlate</summary>

Start from the delta against your baseline. Line up request duration
with CPU, replicas, and request load over the same window.
</details>

<details markdown="1"><summary>Hint: capacity, or something else?</summary>

If the autoscaler added replicas and CPU still isn't saturated, load probably isn't
the whole story. Look at what changed on the booking path around the time latency
moved. You're done when you can describe the symptom precisely and defend a
hypothesis, not when it's fixed.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Confirm the symptom"
        - Open the **Operations Center** and note the **booking / check-in** tile and
          its current P95 latency.
        - Compare that to the baseline you captured in Challenge 1. A jump from
          milliseconds to seconds is a real regression, not just load.

    ??? note "Task 2 · Correlate read-only"
        - In the agent chat, paste the **suggested prompt** above (or ask it to
          correlate `booking` request duration with CPU, replica count, and request
          load over the last 30 minutes).
        - Stay read-only, you're gathering evidence, changing nothing.

    ??? note "Task 3 · Rule out capacity"
        - Check whether the autoscaler (**HPA**) added replicas and whether CPU is
          near its target / request.
        - If replicas scaled and CPU is well under target but latency stays high,
          load alone doesn't explain it. Look at what **changed** on the path (a
          recent deployment / rollout) around the time latency moved.

    ??? note "Task 4 · Record your hypothesis"
        - Ask the agent to write a short summary: the **root cause**, the **two
          independent signals** behind it, and the **least-disruptive recovery** you'd
          propose (do not perform it).
        - Keep it where Challenge 3 can use it: leave it in the chat thread, or save
          it to the agent's **memory** (type `/remember …` in the chat box, which
          becomes `#remember`, or *"save this to your knowledge"*).

### Reference

- [Run a deep investigation](https://learn.microsoft.com/en-us/azure/sre-agent/deep-investigation)
- [Root cause analysis](https://learn.microsoft.com/en-us/azure/sre-agent/root-cause-analysis)
- [Memory and knowledge](https://learn.microsoft.com/en-us/azure/sre-agent/memory)

!!! success "Up next: Controlled recovery under approval"
    With a defensible hypothesis, you're ready to recover check-in under approval and then the flight board goes dark.

    [Proceed to Challenge 3 · Controlled Recovery →](03-controlled-recovery.md){ .md-button .md-button--primary }

---
