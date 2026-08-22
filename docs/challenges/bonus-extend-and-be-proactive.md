# Bonus · Extend & Be Proactive: Custom Tools and the Alert Gap

!!! warning "This is a bonus track, not one of the eight challenges"
    Bonus content sits outside the five acts and outside your progress bar. There is
    no storyboard panel and no fault to find. It pairs naturally with
    [Challenge 5](05-engineer-the-agent.md), where you first shaped what the agent
    *is*, but it needs the incident history of a full day — so take it after
    [Challenge 8](08-leadership-briefing.md), or come back to it later.

    **Run mode:** Review · **Governance:** read-only investigation, artifacts only

**Situation.** Every incident today started the same way: something broke, and *you*
noticed. You ran `start-challenge.ps1`, you read the Operations Center, you went
looking. At no point did Aetherion tell you that anything was wrong.

That is not an accident of the lab. Look at what this environment actually monitors:

```powershell
az monitor metrics alert list -g <resource-group> --query "[].{name:name, severity:severity, enabled:enabled}" -o table
```

One rule. **Failed requests on Application Insights, at Sev1** — the one Challenge 6
binds a response plan to and Challenge 7 depends on firing.

(Your resource group name is in `scripts/.env.aetherion.json` if you have lost it.)

Now line that single rule up against the day you have just had.

| Incident | What it looked like | Failed requests? | Would it have paged anyone? |
|---|---|---|---|
| Check-in slowdown (C2) | `booking` at ~3 s, **0 % errors** | No | **No** |
| Flight board dark (C3) | `flight-ops` pods never start | Yes | Yes |
| Crew scheduling timing out (C4) | `crew-scheduling` at ~1.5 s, **0 % errors** | No | **No** |
| Baggage canary (C6) | A slice of requests returning errors | Yes | Yes |
| Major incident (C7) | Four tiers, front door failing | Yes | Yes |

**Two of the five are invisible.** Both latency-only, both passenger-facing, and
both are the incidents this workshop spent the most time teaching you to
investigate. In production nobody would have run a script to tell you they had
started.

**Mission.** Close that gap the way an SRE actually does it — audit the coverage you
have against the incidents you know happened, then have the agent hand you the
detections you are missing as reviewable code rather than advice.

<div class="grid cards" markdown>

- :material-radar: **Proactive, not reactive**: find the alerts you don't have before the incident you haven't had
- :material-code-braces: **Artifacts, not opinions**: KQL and Bicep you can review, commit and deploy
- :material-toolbox-outline: **Extensibility**: give the agent a signal only Aetherion has

</div>

### Tasks

1. **Inventory the coverage.** Establish what actually alerts today, at what severity, and wired to what.
2. **Map incidents to coverage.** Work out which of today's five incidents would have reached a human, and which would have run silently until a passenger complained.
3. **Get the missing detections as code.** Have the agent write the KQL and the alert rule for a latency-only failure, grounded in the telemetry this environment really emits.
4. **Optional · give the agent Aetherion's own signal.** Wrap the Operations Center health API as a custom MCP tool so the agent can read per-service percentiles directly.

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Audit the alert coverage on this resource group. List every alert rule, its
    severity and whether it is enabled. Then tell me which of these would have
    fired, and which would not: a service serving every request successfully but
    at 3 seconds instead of 20 milliseconds; and a service returning HTTP 500 on
    a slice of traffic. For anything not covered, propose a detection. Do not
    create or modify any alert rules.

### Success criteria

- You can name, from evidence rather than assumption, which of today's incidents would have paged a human and which would not.
- The agent produced a **latency-based detection as KQL** you can run against Application Insights and see return rows.
- You have an **alert rule as Bicep or ARM** that you could put through code review, with a severity you can justify against the existing Sev1 rule.
- You can explain why a latency alert is harder to get right than an error-rate alert, and what you chose for the threshold and window.

!!! warning "Do not deploy a paging alert into the lab"
    Treat the output as artifacts. Deploying a live rule that pages, in an
    environment you are about to tear down, teaches nothing and risks firing into
    whatever action group you point it at. If you want to see it work, wire it to
    the existing action group, which has no receivers.

### Hints

<details markdown="1"><summary>Hint: why the latency incidents were invisible</summary>

The gateway probes each service and reports `p50Ms`, `p95Ms` and `errorRatePct`. In
the `cache-endpoint` and `slow-query` incidents the error rate stayed at **0 %** —
every request succeeded, it just took thousands of milliseconds. A rule watching
`requests/failed` has nothing to count.

This is the single most common real-world alerting gap: teams alert on failure
because it is easy to define, and their worst outages are slow rather than broken.

</details>

<details markdown="1"><summary>Hint: what telemetry you actually have to work with</summary>

Application Insights receives request telemetry from the gateway and services, so
`requests` carries `duration`, `success`, `resultCode` and the operation name. That
is enough for a percentile-based detection.

Since you enabled managed Prometheus at provisioning time, container CPU and memory
time series are also queryable — useful for a saturation alert, but be careful:
CPU is a *cause*, not a symptom. Alert on what the passenger experiences.

</details>

<details markdown="1"><summary>Hint: a threshold you can defend</summary>

Aetherion's stated budget for a passenger-facing path is **400 ms** at p95 — the
same number the Operations Center ambers at. A detection that fires the instant a
single request crosses 400 ms will page you constantly; one that needs a
five-minute average will let a departure wave pass before it speaks.

Ask the agent to justify the window and the `for` duration, not just the number.

</details>

### Task detail

??? note "Task 1 · Inventory the coverage"
    Ask the agent, and verify it yourself:

    ```powershell
    az monitor metrics alert list -g <resource-group> -o table
    az monitor action-group list -g <resource-group> -o table
    ```

    Note what the action group does **not** have: any receivers. The alert is real
    and it fires, but it pages nobody. That is worth sitting with — an alert with no
    receiver looks identical to good coverage on a dashboard.

??? note "Task 2 · Map incidents to coverage"
    Go through the table at the top of this page yourself before you ask the agent.
    You lived through all five, so you know the shape of each one.

    The question to answer precisely: *for each incident, which signal crossed which
    threshold, and was anything watching it?*

    Then have the agent check your reasoning against the telemetry rather than
    against your memory of it.

??? note "Task 3 · Get the missing detections as code"
    Ask for the detection first:

    > Write me a KQL query against Application Insights that would detect the
    > check-in slowdown: requests succeeding but p95 duration far above our 400 ms
    > budget, grouped by service, over a five-minute window. Then run it against
    > the last two hours so I can see whether it actually returns the incidents
    > from today.

    A detection you have not run is a guess. Because the incidents really happened
    in this workspace, a correct query returns real rows — that is the whole value
    of doing this at the end of the day rather than on a whiteboard.

    Then ask for the rule:

    > Now express that as an Azure Monitor scheduled query rule in Bicep, at a
    > severity consistent with the existing `major-incident` rule, wired to the
    > existing action group. Explain your choice of severity, evaluation window
    > and threshold. Do not deploy it.

    Review it the way you would review a colleague's PR. Check the severity against
    the Sev1 rule the response plan matches on — if you make this Sev1 too, it will
    trigger the Challenge 6 response plan, which may or may not be what you want.

??? note "Task 4 · Optional · give the agent Aetherion's own signal"
    Everything above works from Azure's telemetry. But Aetherion already computes
    exactly the signal you want, per service, and the agent cannot see it:

    ```
    GET /api/status  →  { services: { crew: { p50Ms, p95Ms, errorRatePct, ok } }, overall }
    ```

    This is the general case of a real problem: **the most useful signal in your
    organisation is usually the one only your platform knows.** Alert rules can't
    reach it, and no built-in tool knows it exists.

    In Challenge 8 you connected someone else's MCP server. The same protocol lets
    you publish your own: a small server exposing one tool, `get_platform_health`,
    that calls the Ops Center API and returns the per-service percentiles. The agent
    then reasons over Aetherion's own view of itself alongside Azure's.

    !!! note "Scope check before you build it"
        This is the one part of this page that needs something the lab does not
        already run: the agent reaches MCP servers over the network, so a local
        script is not enough — it has to be hosted somewhere reachable, with
        authentication in front of it.

        Treat it as a design exercise unless you have somewhere to put it. Sketch
        the tool contract, decide how it authenticates, and decide who in your
        organisation would own it. That conversation is the valuable part; the
        server is thirty lines.

    Worth deciding deliberately: a tool the agent can call for live health is
    powerful during an incident, and it is also a new dependency and a new piece of
    attack surface. The [hooks and policies bonus](bonus-hooks-and-policies.md)
    covers how you would constrain it.

### Reference

- [MCP connectors and tools](https://learn.microsoft.com/en-us/azure/sre-agent/mcp-connectors)
- [Log alerts in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-types#log-alerts)
- [Application Insights request telemetry](https://learn.microsoft.com/en-us/azure/azure-monitor/app/data-model-complete#request)
- [Managed Prometheus in AKS](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-enable)

---

[Back to the finish line →](finish.md){ .md-button }
