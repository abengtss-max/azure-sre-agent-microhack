# :material-flag-checkered: Finish — you kept Aetherion flying

!!! success "MicroHack complete"
    You onboarded a read-only agent, investigated and recovered live incidents under
    approval, grounded the agent in Aetherion's runbooks, engineered a specialist
    subagent and reusable skill, let it recover autonomously within guardrails,
    commanded a Tier-0 major incident, and briefed leadership. That's the full
    **Reactive → Assisted → Autonomous** journey with the Azure SRE Agent.

### What you can now do

<div class="grid cards why-cards" markdown>

- :material-radar: **Detect & investigate** incidents read-only, with evidence-backed root cause
- :material-account-check-outline: **Recover safely** under approval or bounded autonomy
- :material-book-open-variant: **Ground & extend** the agent with runbooks, subagents and skills
- :material-file-chart-outline: **Close the loop** — RCA handover and a leadership briefing

</div>

### Tear down the environment

!!! warning "Do this to stop Azure charges"
    ```powershell
    ./scripts/99-teardown.ps1 -ResourceGroup rg-aetherion-microhack
    ```

    This removes the resource group — the single biggest cost saver. See
    [Teardown](../reference/commands.md#teardown) for the reset-vs-delete options.

### Where to go next

- **Use it for real:** [Azure SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) · [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions) · [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)
- **Go deeper on this build:** [Architecture](../reference/architecture.md) · [Service catalog](../reference/service-catalog.md) · [Commands](../reference/commands.md)
- **Found it useful?** Star the repo and share feedback on [GitHub](https://github.com/abengtss-max/sreagentmicrohack).

---

*Want another run? Reopen [Challenge 1](01-onboard-and-baseline.md) — use the **Reset progress** link on the progress bar to start fresh.*
