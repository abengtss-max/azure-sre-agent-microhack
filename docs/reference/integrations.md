# Integrations

The Azure SRE Agent is designed to sit inside your existing operations toolchain,
not replace it. It grounds its reasoning in your source of truth (code and
runbooks), receives signals from your monitoring stack, and hands work off to the
systems your team already lives in.

In this MicroHack, **GitHub** is the hands-on integration. The agent reads the
Aetherion AirOps repository to correlate incidents with recent changes. The
remaining integrations are listed so you understand the wider picture when you take
the agent back to your own environment.

## Source control & change correlation

| Integration | What the agent does with it |
|-------------|-----------------------------|
| **GitHub** *(used in this hack)* | Reads the repo to correlate incidents with recent commits/PRs, cite the change that likely caused a regression, and suggest fixes. |
| **Azure DevOps (Repos & Boards)** | Same change-correlation over Azure Repos; can reference work items for context. |

## Signals & telemetry

| Integration | Role |
|-------------|------|
| **Azure Monitor / Application Insights / Log Analytics** *(used in this hack)* | Primary signal plane: metrics, traces, logs, and the **Sev1 alert** that triggers a response plan in Challenge 7. |
| **Grafana** *(used in this hack)* | Dashboards for autoscaling and latency correlation. |
| **Datadog · Dynatrace · Splunk** | Ingest signals from third-party observability platforms where they are the team's system of record. |

## Incident & ticketing

Not used in this hack. In your own environment the agent can push findings and
follow-up actions to **ServiceNow**, **PagerDuty**, or **Jira** so incidents,
paging, and corrective work stay in the systems your team already uses.

## How to think about integrations in this hack

- **Ground first.** Point the agent at the code and runbooks that define "correct"
  before you point it at dashboards. Challenge 3 and Challenge 7 both lean on
  change correlation.
- **Signals in, actions out.** Monitoring integrations tell the agent *something is
  wrong*; ticketing/paging integrations make sure the *right humans* are looped in
  when the agent hands back.
- **Bring your own.** The patterns you practice here (interactive → alert-driven →
  proactive) transfer directly once GitHub is swapped for Azure DevOps, or Azure
  Monitor is joined by Datadog/Splunk.

## Docs

- [Overview](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Permissions & run modes](https://learn.microsoft.com/en-us/azure/sre-agent/permissions)
