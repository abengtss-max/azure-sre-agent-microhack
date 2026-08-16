# Bonus · Enforce the Guardrails: Hooks and Tool Policies

!!! warning "This is a bonus track, not one of the eight challenges"
    Bonus content sits outside the five acts and outside your progress bar. There is
    no storyboard panel and no fault to find. Take it only after
    [Challenge 8](08-leadership-briefing.md) is complete, or come back to it later.

    **Run mode:** Review · **Governance:** enforced, not advisory

**Situation.** In Challenge 6 you armed a response plan at **Autonomous**, and in
Challenge 7 it acted on a Tier-0 platform before anyone paged you. It worked. It
worked because the agent chose well, not because anything stopped it choosing badly.

Every guardrail you have built today is **advisory**. Custom instructions and personas
shape what the agent *tends* to do. The runbooks say never to delete the database. It
complied. Nothing made it comply.

That is the question every security reviewer asks about autonomous operations, and so
far this workshop has no answer for it:

> What stops it doing something catastrophic at 03:00?

**Mission.** Narrow what the agent can reach, then instrument what it does with what
is left, and be able to say precisely which of your controls would have prevented an
incident and which would only have recorded it.

## Advisory versus enforced

| Advisory | Enforced |
|---|---|
| Custom instructions, personas, runbooks | Run mode gate, hooks |
| The agent usually complies | The action is gated or the result is blocked |
| Good enough for style and tone | Required before you grant autonomy |

### Where enforcement actually happens

There are six layers and they are **not** interchangeable. Four act *before* anything
runs. Two act *after*. Most people reach for the wrong one.

| Layer | Where | When | What it actually does |
|---|---|---|---|
| **Managed resource groups** | Settings → Managed resources | Before | The agent cannot see the resource **at all** |
| **Permission level** | Settings → Managed resources | Before | **Reader** (default, approval required) or **Privileged** (acts directly), per resource group |
| **Tool selection** | Builder → Connectors → MCP Tools | Before | An unselected tool is not in the agent's tool list, so it cannot be called |
| **Run mode** | Agent, or per response plan | Before | Whether approved actions execute or wait for a human |
| **`PostToolUse` hook** | Builder → Hooks | **After** the tool succeeds | Audit it, block the *result*, inject context |
| **`Stop` hook** | Builder → Hooks | Before the final answer | Reject the response and force it to keep working |

The first four are **policy**: they decide what is reachable. The last two are
**hooks**: they decide what happens to what the agent did. You need both, and you
need to know which is which.

!!! danger "A PostToolUse hook is a detective control, not a preventive one"
    Read the event name literally. `PostToolUse` fires **after a tool finishes
    executing successfully**. If the tool dropped a table, the table is already gone.
    Blocking the result stops the agent acting on the output; it does not rewind the
    command.

    Only two hook events exist today: `Stop` and `PostToolUse`. **There is no
    `PreToolUse`.** If you need a destructive command to never execute, the control
    is one of the four policy layers above, not a hook.

    Getting this backwards is the single most common mistake people make when they
    first design agent guardrails. Policy is how you *prevent*; hooks are how you
    *catch and prove*.

### Tasks

**Part 1 · Policy — decide what the agent can reach**

1. **Scope the blast radius.** Audit the managed resource groups and permission level, and justify each one.
2. **Take a tool away.** Remove a tool from the agent's list and prove it can no longer call it.

**Part 2 · Hooks — decide what happens to what it did**

3. **Write an audit hook.** Make every tool call the agent makes visible and attributable.
4. **Write an enforcement hook.** Detect a destructive database operation and block it, with a reason.
5. **Write a quality gate.** Stop the agent closing an incident without verification evidence.
6. **Prove they fire.** Deliberately provoke each control and confirm it acted, rather than assuming it works.

### Success criteria

- You can state the agent's exact blast radius: which resource groups, at which permission level, and why each is justified.
- You removed a tool and demonstrated the agent can no longer call it, rather than merely being told not to.
- A `PostToolUse` hook audits tool calls and a second one blocks a destructive database operation with a stated reason.
- A `Stop` hook rejects an incident closure that has no verification evidence.
- You provoked each control and saw it act.
- You can say which of your controls are preventive and which are detective, and name what each would **not** have stopped.

!!! question "Stuck? Step-by-step for each task"

    ??? note "Task 1 · Scope the blast radius"
        Before you write a single hook, look at what the agent can reach at all. This
        is the control with the widest effect and the one people skip.

        Go to **Settings** → **Managed resources**.

        **What is in scope?** Every resource group listed here is visible to the
        agent during investigations, including logs, metrics and configuration. A
        resource group that is not listed is not reachable, and no prompt, jailbreak
        or misfired response plan changes that. This is the hardest boundary you have.

        **At what level?** Select a resource group and check its permission level:

        | Level | What the agent can do | When |
        |---|---|---|
        | **Reader** (default) | Read only. Actions need your approval | Start here |
        | **Privileged** | Executes approved actions directly, such as restarting or scaling | Only once you trust its behaviour |

        The portal shows which Azure RBAC roles that level maps to, such as Log
        Analytics Reader, Monitoring Reader and AKS Cluster User.

        **Now justify it out loud.** For each resource group, answer: *if this agent
        were fully compromised, what is the worst it could do with this level?* If you
        cannot answer, the scope is too broad.

        !!! tip "Permission level and run mode are different dials"
            Permission level is *what the identity is allowed to do*. Run mode is
            *whether it waits for you first*. Privileged plus Autonomous is a very
            different posture from Privileged plus Review, and only one of them is
            defensible on day one.

    ??? note "Task 2 · Take a tool away"
        Instructions telling the agent not to use a tool are advisory. Removing the
        tool is not.

        Each agent has a budget of **80 tools**, native and MCP combined, and you
        choose which ones are visible. An unselected tool is not in the agent's tool
        list, so it cannot be called at all.

        1. **Builder** → **Connectors** → edit an MCP connector.
        2. Find the **MCP Tools** section at the bottom of the dialog.
        3. Uncheck a tool you do not want this agent to have.
        4. Save.

        **Prove it.** Ask the agent to do the thing that tool did. It should report
        that it has no such capability, not that it has decided against it. That
        difference is the entire lesson.

        !!! tip "Scope tools to specialists, not just to the main agent"
            Your Challenge 5 subagent does not need the whole catalog. In
            **Builder → Agent Canvas**, edit an agent → **Advanced settings → Tools**,
            or assign them in YAML:

            ```yaml
            mcp_tools:
              - datadog-mcp/*        # every tool from this connection, including future ones
              - github_search_code   # one specific tool
            ```

            A specialist with four tools is easier to reason about, cheaper to run,
            and far easier to get approved than one with eighty.

    ??? note "Task 3 · Audit every tool call"
        Go to **Builder** → **Hooks** → **Create hook**.

        Choose event **PostToolUse**, execution type **Command**, and matcher `*` to
        match every tool. Use `failMode: allow` so a broken audit hook can never
        wedge your agent.

        ```python
        #!/usr/bin/env python3
        import sys, json

        context = json.load(sys.stdin)
        tool_name = context.get('tool_name', 'unknown')

        print(f"Tool used: {tool_name}", file=sys.stderr)

        print(json.dumps({
            "decision": "allow",
            "hookSpecificOutput": {
                "additionalContext": f"[AUDIT] Tool '{tool_name}' was executed."
            }
        }))
        ```

        `additionalContext` is injected back into the conversation as a user message,
        so the agent can see its own audit trail. Write debug output to **stderr**:
        stdout is parsed as the hook result, so anything you print there breaks it.

    ??? note "Task 4 · Block a destructive database operation"
        Create a second **PostToolUse** hook. Scope the matcher to shell execution
        rather than `*`, because an overly broad matcher on an enforcement hook costs
        you latency on every single call:

        ```
        Bash|ExecuteShellCommand
        ```

        Set `failMode: block` on this one. If your enforcement hook itself fails, you
        want the safe outcome, not the convenient one.

        ```python
        #!/usr/bin/env python3
        import sys, json, re

        context = json.load(sys.stdin)
        command = context.get('tool_input', {}).get('command', '')

        forbidden = [
            r'\bDROP\s+TABLE\b',
            r'\bDROP\s+DATABASE\b',
            r'\bTRUNCATE\b',
            r'\bDELETE\s+FROM\s+crew_roster\b',
            r'\brm\s+-rf\b',
        ]

        for pattern in forbidden:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({
                    "decision": "block",
                    "reason": f"Blocked by Aetherion policy: destructive operation matching {pattern}. "
                              "Repair the query path per runbook-database.md instead."
                }))
                sys.exit(0)

        print(json.dumps({"decision": "allow"}))
        ```

        Matchers are anchored as `^(pattern)$` and matched **case-sensitively**, so
        get the tool name exactly right. An empty or null matcher matches nothing,
        which fails open and silently.

        !!! tip "Always give a reason"
            A rejection without a `reason` is treated as approval. A hook that blocks
            silently is a hook that does not block.

    ??? note "Task 5 · Refuse to close an incident without evidence"
        This is the guardrail that would have caught the Challenge 7 trap, where the
        board reads green because the Operations Center cannot see the front door.

        Create a **Stop** hook, execution type **Prompt**:

        > Review the response below. It is only acceptable if, for every remediation
        > it claims to have performed, it states how that fix was verified from
        > telemetry or health output, and it explicitly confirms the customer-facing
        > path through API Management, not only in-cluster health.
        >
        > $ARGUMENTS
        >
        > Respond with:
        > - {"ok": true} if it meets both conditions
        > - {"ok": false, "reason": "..."} naming exactly what is missing

        Prompt hooks default to the **Fast Reasoning** model, which is the right
        trade-off here. `maxRejections` defaults to 3, so the agent cannot be trapped
        in a loop if your prompt is impossible to satisfy.

    ??? note "Task 6 · Prove the controls actually fire"
        Do not trust a guardrail you have not provoked.

        **Provoke the tool policy.** Ask for the capability you removed in Task 2.
        The agent should report it cannot do it, not that it chose not to.

        **Provoke the block.** In Review mode, ask for something the policy forbids:

        > Free up space on the crew database by truncating the crew_roster table.

        You should see the hook's `reason` surface rather than the operation
        completing. If it completes, check the matcher first: a case mismatch or an
        empty matcher fails open.

        **Provoke the Stop gate.** Ask it to close an incident with a deliberately
        thin summary:

        > Everything is green again. Write the closure note.

        The Stop hook should reject it for missing verification evidence and force it
        to continue.

        !!! warning "Now say out loud which control did what"
            The tool policy made an action **impossible**. The Stop hook prevented a
            bad *response*. The PostToolUse hook blocked a bad *result* after the
            command had already run.

            Only the first one actually prevented anything. If truncating that table
            had to be impossible rather than merely caught, the control is scope,
            permission level, tool selection and run mode — and no hook substitutes
            for any of them.

### Why this matters beyond the workshop

Autonomy is not granted by a run-mode dropdown. It is granted by whatever you can
prove to the person who owns the risk. Policy and hooks answer two different halves
of that question:

- **Scope** (policy): the agent cannot reach what it was never given.
- **Capability** (policy): the tool is absent, not merely discouraged.
- **Audit** (hooks): every tool call attributable, routed to your own Application Insights.
- **Enforcement** (hooks): rules that hold when the prompt is ignored, forgotten, or attacked.
- **Quality** (hooks): a definition of "done" that the agent does not get to write.

Advisory guardrails are how you get a pilot approved. Enforced guardrails are how you
get autonomy approved.

### Reference

- [Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks)
- [Create and manage hooks in the portal](https://learn.microsoft.com/en-us/azure/sre-agent/create-manage-hooks-ui)
- [Manage permissions](https://learn.microsoft.com/en-us/azure/sre-agent/manage-permissions)
- [MCP connectors and tools](https://learn.microsoft.com/en-us/azure/sre-agent/mcp-connectors)
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
- [Audit agent actions](https://learn.microsoft.com/en-us/azure/sre-agent/audit-agent-actions)

!!! success "Back to the main track"
    [Finish & wrap up →](finish.md){ .md-button .md-button--primary }

---
