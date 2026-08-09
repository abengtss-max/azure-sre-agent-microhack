# Troubleshooting

Common friction points during setup and delivery. For live application incidents,
that *is* the hack — start from the [Operations Center](../getting-started/environment.md)
and let the agent investigate.

## Setup

??? question "Provisioning fails on a missing resource provider"
    Run `./scripts/00-check-providers.ps1`. It registers the required providers
    idempotently. Registration can take a few minutes to propagate — re-run the
    failed script afterwards.

??? question "`az` commands hit the wrong subscription"
    Confirm the active subscription with `az account show`. Set the right one with
    `az account set --subscription "<subscription-id>"` before re-running.

??? question "AKS pods are not becoming Ready"
    Check events with `kubectl get pods -n aetherion` and
    `kubectl describe pod <name> -n aetherion`. Image pull or resource pressure are
    the usual causes. `./scripts/04-validate.ps1` reports overall health.

??? question "The Operations Center GUI will not load over HTTPS"
    HTTPS is provisioned by `./scripts/03b-setup-https.ps1` (Envoy Gateway +
    Let's Encrypt). Until the certificate is issued, use the direct
    `http://<gateway-public-ip>/` endpoint.

## During the hack

??? question "The agent cannot see or act on a resource"
    This is almost always RBAC. The agent acts through its **own managed identity** —
    grant Reader broadly and narrow write roles only where remediation is intended.
    See [SRE Agent basics](../getting-started/sre-agent-fundamentals.md).

??? question "The agent proposes a plan but never executes"
    That is **Review mode** working as designed — it waits for explicit approval.
    Approve the plan, or promote the fault class to **Autonomous** once you trust it.

??? question "A challenge validation keeps failing"
    Re-read the challenge's **Challenge tasks** section, then run
    `./scripts/check-challenge.ps1 <n>`. If the environment drifted, reset it with
    `./scripts/reset-environment.ps1` and retry.

??? question "The environment is in a weird state after several faults"
    Run `./scripts/reset-environment.ps1` to restore a clean, healthy baseline, then
    re-inject only the fault for the current challenge.

## Still stuck

Re-read the hints in the current challenge and work forward from the evidence in
the Operations Center, Application Insights, and Grafana. Reset with
`./scripts/reset-environment.ps1` if the estate is in a confusing state.
