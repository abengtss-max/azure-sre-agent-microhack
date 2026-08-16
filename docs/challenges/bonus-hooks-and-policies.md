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

**Mission.** Replace one advisory guardrail with an enforced one, and understand
exactly where enforcement can and cannot happen.

## Advisory versus enforced

| Advisory | Enforced |
|---|---|
| Custom instructions, personas, runbooks | Run mode gate, hooks |
| The agent usually complies | The action is gated or the result is blocked |
| Good enough for style and tone | Required before you grant autonomy |

### Where enforcement actually happens

This distinction matters, and it is easy to get wrong.

| Layer | When it acts | What it can do |
|---|---|---|
| **Permission gate** (run mode) | **Before** a tool call runs | Require approval, or refuse the call outright |
| **`PostToolUse` hook** | **After** the tool finishes successfully | Audit it, block the *result*, inject context |
| **`Stop` hook** | Before the agent returns its final answer | Reject the response and force it to keep working |

!!! danger "A PostToolUse hook is a detective control, not a preventive one"
    Read the event name literally. `PostToolUse` fires **after a tool finishes
    executing successfully**. If the tool dropped a table, the table is already gone.
    Blocking the result stops the agent acting on the output; it does not rewind the
    command.

    Only two hook events exist today: `Stop` and `PostToolUse`. **There is no
    `PreToolUse`.** If you need a destructive command to never execute, the control
    is the **run mode permission gate**, not a hook.

    Getting this backwards is the single most common mistake people make when they
    first design agent guardrails. Hooks are how you *catch and prove*; run modes are
    how you *prevent*.

### Tasks

1. **Write an audit hook.** Make every tool call the agent makes visible and attributable.
2. **Write an enforcement hook.** Detect a destructive database operation and block it, with a reason.
3. **Write a quality gate.** Stop the agent closing an incident without verification evidence.
4. **Prove it fires.** Deliberately provoke the hook and confirm it blocked, not just that it logged.

### Success criteria

- A `PostToolUse` hook audits tool calls and a second one blocks a destructive database operation with a stated reason.
- A `Stop` hook rejects an incident closure that has no verification evidence.
- You provoked each hook and saw it fire, rather than assuming it works.
- You can explain, in one sentence each, which control is preventive and which is detective.

!!! question "Stuck? Step-by-step for each task"

    ??? note "Task 1 · Audit every tool call"
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

    ??? note "Task 2 · Block a destructive database operation"
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

    ??? note "Task 3 · Refuse to close an incident without evidence"
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

    ??? note "Task 4 · Prove the hooks actually fire"
        Do not trust a guardrail you have not provoked.

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
            The Stop hook prevented a bad *response*. The PostToolUse hook blocked a
            bad *result* after the command had already run. Neither prevented
            execution. If truncating that table had to be impossible rather than
            merely caught, the control is the run mode gate and a scoped identity,
            and no hook substitutes for it.

### Why this matters beyond the workshop

Autonomy is not granted by a run-mode dropdown. It is granted by whatever you can
prove to the person who owns the risk. Hooks are how you produce that proof:

- **Audit**: every tool call attributable, routed to your own Application Insights.
- **Enforcement**: policy that holds when the prompt is ignored, forgotten, or attacked.
- **Quality**: a definition of "done" that the agent does not get to write.

Advisory guardrails are how you get a pilot approved. Enforced guardrails are how you
get autonomy approved.

### Reference

- [Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks)
- [Create and manage hooks in the portal](https://learn.microsoft.com/en-us/azure/sre-agent/create-manage-hooks-ui)
- [Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview)
- [Audit agent actions](https://learn.microsoft.com/en-us/azure/sre-agent/audit-agent-actions)

!!! success "Back to the main track"
    [Finish & wrap up →](finish.md){ .md-button .md-button--primary }

---
