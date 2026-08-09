# Challenge 4 — Give the Agent Aetherion's Operational Knowledge

!!! abstract "Challenge 04 of 08 · Act II — Human-Guided Operations"
    **Agent mode:** Review → approved write · **Permissions:** Reader → scoped write · **Estimated time:** 20–30 min

    **Stage:** Foundation → **Operations** → Engineering → Autonomous → Major Incident

**Situation.** Crew scheduling is failing — the `crew-scheduling` tile is red while
every other service stays healthy — and duty managers can't confirm who is legal to
fly the evening wave. Out of the box the agent gives generic advice, and a generic
"restart the database" is exactly what Aetherion's runbooks forbid. The fastest path
to the right answer is to ground the agent in your own knowledge.

**Mission.** Ground the SRE Agent in Aetherion's architecture and runbooks so it
recommends the sanctioned fix, then recover `crew-scheduling` with that
non-destructive remediation and verify service is restored.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-book-open-variant: **Ground the agent** — load Aetherion's runbooks and architecture
- :material-target: **Right layer, right fix** — one service down is not the database down
- :material-shield-alert-outline: **Respect guardrails** — relieve the pool, never delete the database
- :material-account-clock-outline: **Legal to fly** — restore crew scheduling before the evening wave

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 4   # open the incident
    ```

### Tasks

1. **Confirm the blast radius** — one service down is not the database being down, so you fix the right layer.
2. **Ground the agent** — load the `knowledge/` runbooks, then re-ask the remediation question and note how the advice changes.
3. **Apply the sanctioned fix** — relieve the pool and stop the leak (never delete the database); verify crew scheduling recovers.

!!! question "Stuck? Full walkthrough available"
    Give each task a genuine attempt before reaching for help — working it out
    yourself is where the learning sticks. Only if you get truly stuck, the
    [Azure portal walkthrough](../getting-started/portal-walkthrough.md) has the
    exact click-by-click for every step.

![Challenge 4 storyboard — Marco, Sam and Aria ground the agent in Aetherion's runbooks](../assets/storyboard/img-challenge-4.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Given `crew-scheduling` is failing on PostgreSQL dependency timeouts while its
    database-backed peers stay healthy, and using the Aetherion runbooks I've
    loaded: what is the sanctioned remediation? Cite the guardrail and give me a
    plan I can approve — do not delete or restart the database.

### Success criteria

- Only `crew-scheduling` is identified as affected.
- The grounded agent cites the runbook guardrail (relieve the pool **and** stop the leak, never delete the database) and you apply that non-destructive fix.
- The tile is green, `/api/crew` recovers, and `check-challenge.ps1 4` passes.

!!! success "Verify your work"

    Run this when you're done — it grades the real end state and unlocks the next challenge:

    ```powershell
    ./scripts/check-challenge.ps1 4
    ```

### Hints

<details markdown="1"><summary>Hint</summary>

Only `crew-scheduling` is red while database-backed peers stay healthy — that
rules out a global database outage. Load the `knowledge/` Markdown files, then
re-ask and watch the advice become Aetherion-specific. The runbook guardrail —
relieve pressure by scaling, never delete the database — is itself the strongest
hint at what's being exhausted (the connection pool).
</details>

### Reference

- [Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard)
- [Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup)
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — make investigation & recovery reusable"
    You've worked several AKS incidents the same way — time to build a specialist and encode a recovery so both are reusable.

    [Proceed to Challenge 5 · Engineer the Agent →](05-engineer-the-agent.md){ .md-button .md-button--primary }

---
