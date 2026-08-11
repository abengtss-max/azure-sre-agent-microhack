# Challenge 5 — Engineer the Agent: Specialist Subagent and Reusable Skill

!!! abstract "Challenge 05 of 08 · Act III — Agent Engineering"
    **Agent mode:** Read-only investigation + approved write · **Permissions:** Reader → scoped write · **Estimated time:** 25–35 min

    **Stage:** Foundation → Operations → **Engineering** → Autonomous → Major Incident

**Situation.** The platform is stable — the right time to invest in tooling. You've
repeated the same Kubernetes triage (pod status, events, rollout history, dependency
health) and the same crew pool-relief recovery across several incidents. Both
investigation *and* recovery are perfect candidates to make reusable.

**Mission.** Build a custom AKS-focused specialist subagent and use it for a scoped
investigation, then encode the crew pool-relief recovery as a reusable skill with
its guardrails intact.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-robot-outline: **Specialist subagent** — scoped AKS triage on demand
- :material-cog-sync-outline: **Reusable skill** — encode the sanctioned recovery once
- :material-shield-check-outline: **Guardrails baked in** — scale, never delete the database
- :material-rocket-launch-outline: **Faster next time** — handle recurrences without re-deriving steps

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 5   # open / set up this challenge
    ```

### Tasks

1. **Build the specialist** — create an AKS reliability triage subagent for the `aetherion` namespace and invoke it explicitly to summarize namespace health and likely causes.
2. **Encode the skill** — capture the crew connection-pool relief from Challenge 4 as a reusable skill, keeping the guardrails (scale, never delete the database), and confirm it loads.
3. **Know the difference** — a subagent is invoked and investigates; a skill auto-loads and encodes a procedure. You'll want both in the final incident.

!!! question "Stuck? Give each task a genuine attempt first"
    Working it out yourself is where the learning sticks. If you need the exact
    clicks, the [Azure portal walkthrough](../getting-started/portal-walkthrough.md)
    has a step for every action.

![Challenge 5 storyboard — Sam and Aria engineer a specialist subagent and reusable skill](../assets/storyboard/img-challenge-5.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat (your new AKS specialist)"
    Act as my AKS reliability specialist for the `aetherion` namespace: triage pod
    status, events, rollout history and dependency health, then summarize the
    namespace's health and the most likely causes. Keep it scoped to AKS.

### Success criteria

- A custom AKS-specialist subagent exists and you've invoked it for a scoped investigation that produces genuinely useful triage.
- A reusable skill captures the sanctioned recovery, loads/applies correctly, and matches the runbook guardrails.
- You can explain when to reach for the subagent versus the skill, and `check-challenge.ps1 5` passes.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 5
    ```

### Hints

<details markdown="1"><summary>Hint</summary>

Decide the specialist's remit in one sentence before creating it — narrow beats
broad — and judge it by whether its output would actually speed up a real AKS
incident. For the skill, reuse the exact steps from Challenge 4 as its backbone and
bake in the guardrails (relieve the pool by scaling, never delete/restart the
database). Skills load automatically and encode procedure; subagents are invoked
and investigate — you want both in the final incident. Respect the 5 concurrent
skills limit.
</details>

### Reference

- [Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)
- [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)
- [Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks)
- [Azure portal walkthrough](../getting-started/portal-walkthrough.md) · [Architecture](../reference/architecture.md) · [Commands](../reference/commands.md)

!!! success "Up next — let the agent run autonomously"
    Now let the agent recover on its own for a small, bounded issue — then make sure it stays cost-effective at scale.

    [Proceed to Challenge 6 · Autonomous & Cost →](06-autonomous-and-cost.md){ .md-button .md-button--primary }

---
