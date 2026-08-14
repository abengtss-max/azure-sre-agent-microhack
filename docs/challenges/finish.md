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

### What changed in your estate

Every incident today was an ordinary change made badly. In a real environment,
these are the five you'd have to undo — and the list is the change-management
lesson in miniature:

| Incident | What changed | How it was undone |
|---|---|---|
| Check-in slowdown | A cost optimisation cut `booking`'s CPU limit and capped its autoscaling | Restore the limit and the ceiling |
| Flight board dark | A release pinned `flight-ops` to an image tag that was never published | `kubectl rollout undo` |
| Crew scheduling | The index behind the crew duty lookup went missing, so every request scanned the whole roster table | Rebuild the index under approval |
| Baggage errors | A canary revision served the wrong API surface behind the same Service | Remove the bad revision |
| API front door | A backend override was published to the APIM product policy | Restore the default policy |

### Tear down the environment

!!! warning "Do this to stop Azure charges"
    ```powershell
    ./scripts/99-teardown.ps1
    ```

    Pick your microhack from the list; it removes the resource group **and** its
    load-generator pair — the single biggest cost saver. See
    [Teardown](../reference/commands.md#teardown) for the reset-vs-delete options.

### Where to go next

- **Use it for real:** [Azure SRE Agent overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) · [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions) · [Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills)
- **Go deeper on this build:** [Architecture](../reference/architecture.md) · [Service catalog](../reference/service-catalog.md) · [Commands](../reference/commands.md)
- **Found it useful?** Star the repo and share feedback on [GitHub](https://github.com/abengtss-max/azure-sre-agent-microhack).

---

*Want another run? Reopen [Challenge 1](01-onboard-and-baseline.md) — use the **Reset progress** link on the progress bar to start fresh.*
