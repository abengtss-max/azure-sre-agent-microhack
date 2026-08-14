# Challenge 5 · Engineer the Agent: Specialist Subagent and Reusable Skill

!!! abstract "Challenge 05 of 08 · Act III: Agent Engineering"
    **Run mode:** Review · **Focus:** builder, no incident to fix

    **Stage:** Foundation → Operations → **Engineering** → Autonomous → Major Incident

**Situation.** The platform is stable, which is the right time to invest in tooling. You've
repeated the same Kubernetes triage (pod status, events, rollout history, dependency
health) and the same crew query-path recovery across several incidents. Both
investigation *and* recovery are perfect candidates to make reusable.

**Mission.** Build a custom AKS-focused specialist subagent and use it for a scoped
investigation, then encode the crew query-path recovery as a reusable skill with
its guardrails intact.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-robot-outline: **Specialist subagent**: scoped AKS triage on demand
- :material-cog-sync-outline: **Reusable skill**: encode the sanctioned recovery once
- :material-shield-check-outline: **Guardrails baked in**: fix the saturated layer, never delete the database
- :material-rocket-launch-outline: **Faster next time**: handle recurrences without re-deriving steps

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 5   # open / set up this challenge
    ```

    Challenge 5 injects no fault — the board stays green while you build.

### Tasks

1. **Build the specialist.** Create an AKS triage subagent for the `aetherion` namespace and invoke it to summarize namespace health and likely causes.
2. **Encode the skill.** Capture the crew query-path recovery from Challenge 4 as a reusable skill, guardrails intact, and confirm it loads.
3. **Know when to use which.** Be able to say when you'd reach for the subagent (invoke to investigate) versus the skill (auto-loads a procedure).

![Challenge 5 storyboard: Sam and Aria engineer a specialist subagent and reusable skill](../assets/storyboard/img-challenge-5.webp){ .story-panel loading=lazy }

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

    Both questions are yours to answer honestly — nothing here changes the platform,
    so the check asks you to confirm what you built:

    ```powershell
    ./scripts/check-challenge.ps1 5
    ```

### Hints

<details markdown="1"><summary>Hint: scope the specialist</summary>

Decide the specialist's remit in one sentence before you build it; narrow beats
broad. Judge it by whether its output would actually speed up a real AKS incident.
</details>

<details markdown="1"><summary>Hint: encode the recovery</summary>

For the skill, reuse the exact steps from Challenge 4 as the backbone and bake in
the guardrails (diagnose which layer is saturated, repair the query path, never
delete or restart the database). Be careful not to encode "scale it" as the answer —
Challenge 4 is precisely the case where scaling cannot work.

Skills auto-load and encode a procedure; subagents are invoked and investigate, so
you'll want both in the final incident.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first, and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Build the specialist"
        - In the agent, go to **Builder → Subagent builder → Create → Custom Agent**.
          Name it (e.g. `aks-triage`) and give it a one-line remit: triage pod
          status, events, rollout history, and dependency health for the
          `aetherion` namespace.
        - Invoke it explicitly and ask for a namespace-health summary with likely
          causes. Judge it on whether it would speed a real AKS incident.

    ??? note "Task 2 · Encode the skill"
        - **Builder → Subagent builder → Create → Skill.** In `SKILL.md`, write the
          crew query-path steps from Challenge 4 (confirm which layer is saturated,
          then repair the query path under approval) and the guardrail (never
          delete/restart the DB, and don't scale the layer that is merely waiting).
        - Save it and confirm it appears in the **Skills** list and loads when
          relevant.

    ??? note "Task 3 · Know when to use which"
        - A **subagent** is something you *invoke* to investigate a domain (your AKS
          specialist).
        - A **skill** *auto-loads* when relevant and encodes a *procedure* (the
          query-path recovery). You'll want both in the final incident.

### Reference

- [Create a subagent](https://learn.microsoft.com/en-us/azure/sre-agent/create-subagent)
- [Create a skill](https://learn.microsoft.com/en-us/azure/sre-agent/create-skill)
- [Subagents overview](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents)

!!! success "Up next: let the agent run autonomously"
    Now let the agent recover on its own for a small, bounded issue, then make sure it stays cost-effective at scale.

    [Proceed to Challenge 6 · Autonomous & Cost →](06-autonomous-and-cost.md){ .md-button .md-button--primary }

---
