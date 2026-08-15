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
        Both the subagent and the skill are created from the same place: in the
        agent, open **Builder** in the left-hand menu, then **Agent Canvas**. The
        canvas shows what your agent is made of — incident response plans,
        subagents, and the tools attached to them.

        Click **+ Create subagent**. The **Create a custom agent** dialog opens.
        Fill it in as follows.

        **Custom agent name**

        ```text
        aks-triage
        ```

        **Instructions** — this is the remit, and it is the field that decides
        whether the specialist is worth having. Paste this, then adjust to taste:

        ```text
        You are an AKS reliability specialist for the `aetherion` namespace.

        Scope: Azure Kubernetes Service only. Investigate pod status, container
        restarts, Kubernetes events, deployment rollout history and the health of
        dependencies as seen from inside the cluster. Do not investigate API
        Management or the database yourself — if the evidence points outside AKS,
        say so and hand back.

        Method: gather evidence before concluding. Prefer `kubectl` output,
        Kubernetes events and rollout history over inference. When a workload looks
        unhealthy, always check whether a recent rollout explains it, and report the
        revision and its change cause.

        Output: a short namespace health summary, the affected workloads, the
        evidence you relied on, likely causes ranked by confidence, and the
        recommended next step. Distinguish clearly between what you observed and
        what you inferred. If required data is unavailable, say what is missing
        rather than assuming.

        Constraints: read-only. Propose remediation, never apply it.
        ```

        The last line matters. Challenge 5 builds a tool while the platform is
        green; the specialist earns write access later, once you have seen it
        reason well.

        **Skills** — leave inherited. Do not select anything here.

        **Tools** — leave inherited. Do not select anything here either. This is
        the one that will catch you out:

        !!! warning "Selecting tools replaces the inherited set — and the picker is incomplete"
            The dialog says the agent inherits 46 global tools and that selecting
            tools *overrides* the defaults. It means replaces, not adds. Select
            three tools and the specialist has three tools.

            That would be fine if the picker showed everything. It doesn't. The
            agent's inherited set includes **`RunKubectlReadCommand`** and
            **`RunKubectlWriteCommand`** under *Azure Operation* — the tools that
            give it the cluster — but searching the picker for `kubectl`, `AKS` or
            `Kubernetes` returns nothing.

            So any selection you make in that panel silently drops cluster access,
            and your AKS specialist ends up unable to read AKS. Scope this
            specialist with its **Instructions**, and leave Tools alone.

        ??? tip "Verify the inherited tools for yourself"
            The picker is not the source of truth. Ask the agent's own API:

            ```powershell
            $base = az resource show -g <resource-group> -n <agent-name> `
              --resource-type Microsoft.App/agents --api-version 2026-01-01 `
              --query properties.agentEndpoint -o tsv

            $tok = az account get-access-token --resource https://azuresre.ai `
              --query accessToken -o tsv

            $r = Invoke-RestMethod "$base/api/v2/agent/tools" `
              -Headers @{ Authorization = "Bearer $tok" }

            $r.data | Where-Object enabled | Select-Object category, name |
              Sort-Object category, name
            ```

            The token audience must be `https://azuresre.ai`; an ARM token is
            rejected. The count of enabled tools should match the number the
            dialog quotes.

        **Hooks** — nothing needed for this challenge.

        Then select **Create**.

        ??? tip "The YAML tab exposes three fields the form hides"
            The **Form / YAML** toggle edits the same definition, but the YAML view
            shows extra keys worth knowing about:

            - `handoff_description` — when the main agent should delegate to this
              specialist. Worth writing, because it is what makes the subagent
              usable in Challenge 7.
            - `agent_type` — the *kind* of subagent: `Autonomous`, `Orchestrator`
              or `Activity`. The portal hardcodes new subagents to `Autonomous`,
              and it is **not** the Review / Autonomous run mode — that is a
              separate agent-level setting. Leave it as generated.
            - `enable_skills` — whether the specialist can load skills, including
              the one you are about to author.

        Then invoke the specialist and ask for a namespace-health summary with
        likely causes. Judge it on one question: would this have sped up a real AKS
        incident?

    ??? note "Task 2 · Encode the skill"
        Exactly the same path — **Builder → Agent Canvas** — but click
        **+ Create skill** instead. (**Builder → Skill Builder** in the left-hand
        menu takes you to the same place.)

        **Name**

        ```text
        crew-query-path-recovery
        ```

        **Description** — behind the **Edit** link, and the field most people skim.
        Skills auto-load by context, and this description is what the agent matches
        on when it decides whether the skill is relevant. Describe *when to reach
        for it*, not what it does:

        ```text
        Use when crew scheduling is slow or timing out and the pods themselves look
        healthy and underutilised — the symptom of a saturated shared database
        rather than a saturated workload. Also use when several services sharing one
        database degrade together while unrelated services stay fast.
        ```

        **SKILL.md** — the editor on the right is pre-scaffolded with `name` and
        `description` frontmatter and a placeholder comment. Fill in the frontmatter
        and replace the comment:

        ```markdown
        ---
        name: crew-query-path-recovery
        description: Recover crew scheduling when a saturated shared database, not the workload, is the bottleneck.
        ---

        ## When this applies

        `crew-scheduling` is slow or timing out, but its pods are healthy, not
        restarting, and using little CPU. Peer services sharing the same PostgreSQL
        server are also degraded; services that do not share it are unaffected.

        ## Diagnose before acting

        1. Confirm the pods are waiting, not working: check pod CPU against requests
           and confirm no restarts.
        2. Confirm the autoscaler is not the constraint. If CPU is below target the
           autoscaler will refuse to add replicas, and it is right to refuse.
        3. Confirm the database is the saturated layer: check PostgreSQL CPU.
        4. Identify the query path behind the crew duty lookup and whether it is
           supported by an index.

        ## Remedy

        Repair the query path — restore the missing index supporting the crew duty
        lookup. Build it without taking a disruptive lock on a live table.

        Verify by re-measuring crew latency under the same load, not by checking
        that a pod restarted.

        ## Guardrails

        - Never delete or restart the database. It is a shared dependency and the
          blast radius is every service on it.
        - Do not scale the layer that is merely waiting. Adding replicas to
          `crew-scheduling` adds connections to an already-saturated database and
          makes it worse.
        - Any write is proposed for approval first, never applied unilaterally.
        - If the evidence does not show database saturation, this skill does not
          apply — stop and say so.
        ```

        **Files** — `SKILL.md` on its own is enough. You can attach more files or a
        folder if you want to split a longer procedure up.

        **Tools** — leave empty. The dialog itself advises configuring tools on the
        agent rather than the skill, for more consistent behaviour.

        Then select **Create**.

        The guardrails are the point of this task. A skill that says "crew is slow,
        add replicas" would be actively harmful here — Challenge 4 is precisely the
        case where scaling cannot work. Encoding *why not* is what makes it worth
        keeping.

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
