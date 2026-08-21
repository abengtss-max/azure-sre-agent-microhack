# What is the Azure SRE Agent?

**Azure SRE Agent is an AI teammate for operating production on Azure.** It watches
your live estate, investigates incidents like an experienced site reliability
engineer, explains the likely root cause with evidence, and, with your approval or
within guardrails you set, remediates. It reasons across every tier: containers
(AKS), the API front door (APIM), databases, caches, and the telemetry that ties
them together, not just one service.

### What it does

- **Detects & triages**: correlates metrics, logs, traces, resource health and recent changes (Azure Activity Log + GitHub) to find what broke and when.
- **Investigates read-only**: produces an evidence-backed root-cause hypothesis before anyone touches production.
- **Remediates safely**: proposes a least-disruptive plan you approve, or acts autonomously within a bounded, RBAC-scoped posture.
- **Learns your operations**: grounds in your runbooks and architecture, and remembers past incidents so recurrences resolve faster.
- **Extends to your team**: custom specialist subagents, reusable skills, alert-triggered response plans, scheduled health checks, and a Python sandbox for reports.

### Why it matters

- **Faster recovery (lower MTTR)**: tireless, parallel investigation shrinks the time from alert to root cause.
- **Less on-call toil**: routine triage and well-understood fixes are handled for you, so engineers focus on the hard problems.
- **Governed by design**: every action runs under Azure RBAC and is attributable and auditable; you decide how much autonomy to grant.
- **Consistent & institutional**: the same sanctioned runbook steps run every time, and hard-won knowledge doesn't leave with the on-call.

!!! tip "You'll build exactly this across the hack"
    Onboard it read-only, investigate an incident, recover under approval, ground it
    in your runbooks, engineer a subagent + skill, let it recover autonomously within
    guardrails, command a major incident, and brief leadership.

## How you control it: two independent dials

**Permissions** (Azure RBAC, what the agent's identity is *allowed* to do) and
**run mode** (*how* it acts: **Review** proposes and waits for approval;
**Autonomous** acts within its permissions and guardrails) are the two controls
that matter all day. You start read-only and earn autonomy.

| Control | Options | What it decides |
|---|---|---|
| **Permissions** (Azure RBAC) | Reader → narrow scoped write | What the agent's identity is *allowed* to do |
| **Run mode** | Review · Autonomous | *How* it acts: propose-and-wait vs act within guardrails |

Everything else, including on-behalf-of approval, skills vs subagents, the knowledge base,
and the agent's own telemetry resources, is in
[Appendix A: Azure SRE Agent fundamentals](#appendix-a).
Read it once when you have a spare minute; you do not need it all before you start.

Documentation you will return to all day:
[Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) ·
[Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)

---


## Appendix A: Azure SRE Agent fundamentals { #appendix-a }

Read this once when convenient. The two controls from *Azure SRE Agent in one
minute* are the core; everything below rounds out the picture.

**Two independent controls.**

1. **Permissions (Azure RBAC):** what the agent's identity is *allowed* to do (for
   example Reader vs a narrower write role). When it lacks permission it can fall
   back to **on-behalf-of (OBO)** and ask you to approve using *your* credentials.
2. **Run mode:** *how* it acts. **Review** (proposes, waits for approval) vs
   **Autonomous** (acts within its permissions and guardrails).

**Other essentials.**

- **Subagents are invoked explicitly**, in natural language, by naming the one you
  want (*"delegate this to your `aks-triage` subagent"*). There is no slash-command
  syntax, and asking the agent to *act as* a specialist does not invoke one, it just
  adopts the persona.
- **Skills** are matched against their description rather than guaranteed to fire.
  Name the skill when you want it used. Skills are capped at **5 concurrent active**
  at a time.
- Only a user with the **Azure SRE Agent Administrator** role can approve proposed
  actions.
- The **knowledge base** accepts Markdown/text files (this repo's `knowledge/`),
  which is how you ground the agent in Aetherion's runbooks and standards.
- Creating an agent also provisions its **own** Application Insights, Log
  Analytics, and managed identity, separate from the application's telemetry.

**Documentation you will return to all day:**
[Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview) ·
[Create and set up](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up) ·
[Complete your setup](https://learn.microsoft.com/en-us/azure/sre-agent/complete-setup) ·
[Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions) ·
[Security overview](https://learn.microsoft.com/en-us/azure/sre-agent/security-overview) ·
[Team onboarding & memory](https://learn.microsoft.com/en-us/azure/sre-agent/team-onboard) ·
[Subagents & extensibility](https://learn.microsoft.com/en-us/azure/sre-agent/sub-agents) ·
[Skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills) ·
[Agent hooks](https://learn.microsoft.com/en-us/azure/sre-agent/agent-hooks) ·
[Pricing & billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing)
