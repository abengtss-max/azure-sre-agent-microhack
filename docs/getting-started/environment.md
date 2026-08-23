# Set up the environment

This is the only setup step. One command provisions the entire Aetherion AirOps
platform on Azure, then hands you straight to Challenge 1.

## 1. Install the required tools (Windows)

| Tool | Minimum version | Notes |
|------|-----------------|-------|
| PowerShell | 7.0 | required |
| Azure CLI | 2.60 | required |
| kubectl | any recent | required |
| Git | any recent | required |
| GitHub CLI (`gh`) | any recent | optional, but the steps below and Challenge 8 give `gh` one-liners, and the Challenge 8 grader uses it to confirm your work instead of asking you |

```powershell
winget install --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements
winget install --id Microsoft.AzureCLI --exact --accept-source-agreements --accept-package-agreements
winget install --id Kubernetes.kubectl --exact --accept-source-agreements --accept-package-agreements
winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements
winget install --id GitHub.cli --exact --accept-source-agreements --accept-package-agreements
```

After installs complete, restart your terminal so the commands are available on
PATH, and sign in to the GitHub CLI once with `gh auth login`.

!!! warning "Run every command in PowerShell 7 (`pwsh`)"
    Windows PowerShell 5.1 is the default on Windows and is **not** supported: the
    scripts stop with a version error. Start your session with `pwsh` and confirm
    with `$PSVersionTable.PSVersion` (must be 7.0 or later).

## 2. Get the two repositories

You use **two** repositories in this MicroHack:

**a) Clone the lab repo.** It drives the hack (challenges + scripts):

```powershell
git clone https://github.com/abengtss-max/azure-sre-agent-microhack.git
cd azure-sre-agent-microhack
```

**b) Fork the application repo.** This is the Aetherion AirOps *application*
source that the Azure SRE Agent connects to for change correlation. Fork it to
**your own account** so the agent can read its history and open pull requests:

1. Open <https://github.com/abengtss-max/aetherion-airops-platform>
2. Click **Fork** (keep the default name).
3. In your new fork, go to **Settings → General → Features** and tick
   **Issues**.

You'll connect the SRE Agent to **your fork** in Challenge 1.

!!! warning "Step 3 is not optional"
    **GitHub turns Issues off on every new fork**, regardless of the upstream
    setting. Challenge 8 has the agent file the incident RCA as an issue on your
    fork; if Issues are disabled the call fails with `HTTP 410 Issues are
    disabled for this repository` and there is nothing wrong with your agent or
    your token. Enable it now and you will not meet it eight challenges later.

    Check it from the CLI if you prefer:

    ```powershell
    gh api repos/<your-org>/aetherion-airops-platform --jq .has_issues   # must be true
    gh api -X PATCH repos/<your-org>/aetherion-airops-platform -F has_issues=true
    ```

!!! danger "Connect the agent to your fork, never to the lab repo"
    **Never connect the Azure SRE Agent to the lab repo because it contains the
    challenge material** and would spoil every investigation. Connect the agent
    **only to your fork of `aetherion-airops-platform`**.

**c) Create a GitHub Personal Access Token now.** Challenge 8 has the agent write
back to your fork — it files the incident RCA as an issue and opens a pull request
— and the GitHub MCP connector it uses for that accepts **a PAT only**. There is no
OAuth option on that connector.

!!! danger "Do this on day one, not at Challenge 8"
    In many organisations a fine-grained PAT against an **org-owned** repository
    needs **owner approval**, which is not instant. If you find that out at
    Challenge 8 you will not finish the hack that day.

    Create the token against your fork with:

    - **Contents: Read and write** — create a branch and commit to it
    - **Pull requests: Read and write** — open the PR
    - **Issues: Read and write** — file the RCA

    A classic token with `repo` scope also works. A read-only token **connects
    successfully and then fails on the first write**, which looks like a broken
    connector rather than a permissions problem.

    Forking to your **personal** account instead of an organisation avoids the
    approval step entirely.

## 3. Check you have access

- **Azure subscription** with **Owner** (or Contributor + User Access
    Administrator). The provisioner deploys infrastructure and assigns the agent's
  managed identity.
- This repository cloned locally and opened in VS Code.

```powershell
az login
az account set --subscription "<subscription-id>"
```

## 4. Run one command

```powershell
./scripts/provision-environment.ps1
```

That's it. It runs preflight → deploy infrastructure → build & push images → deploy the app →
validate, then opens the Operations Center, Grafana, and the resource group in
your browser. The script is idempotent and safe to re-run if a step fails: it
resolves the cluster's current Kubernetes version rather than forcing a downgrade,
and the network configuration is declared explicitly so a re-run cannot reset it.

Each run provisions into a **uniquely named** resource group,
`rg-aetherion-microhack-<suffix>` (for example `rg-aetherion-microhack-a7c3`), in
`swedencentral`. The script **prints the exact name** when it finishes. Use that
name wherever these docs mention *your resource group*, and when you scope the
Azure SRE Agent to it. Because every run is unique, multiple attendees can share a
single subscription and you can safely re-provision without collisions.

Override the base name or region with `-ResourceGroup`, `-Location`, or
`-NamePrefix`; the unique suffix is always appended.

!!! warning "Re-provisioning leaves the previous environment running"
    Because each run creates a **new** suffixed resource group, re-provisioning
    does **not** replace your earlier environment. The previous one keeps running
    (and billing), and a stray copy can confuse the agent if you scope it to the
    wrong one. If you re-provision, either reuse the environment you already have,
    or tear down the old ones. The teardown script lists every
    `rg-aetherion-microhack-*` environment (each with its paired `-loadgen` group)
    and lets you pick which to delete:

    ```powershell
    ./scripts/99-teardown.ps1        # pick an environment to delete
    ./scripts/99-teardown.ps1 -All   # delete all lab environments
    ```

    Always scope the Azure SRE Agent to your **current** resource group, using the name
    the provisioner printed when it finished.

## 5. What gets deployed

[![Aetherion AirOps: Azure SRE Agent MicroHack environment architecture](../assets/architecture/aetherion-architecture.png){ .arch-diagram loading=lazy }](../assets/architecture/aetherion-architecture.png)

*Request/data flow runs left to right (solid blue); telemetry and control flow to
observability and the Azure SRE Agent (dashed purple); alerting is shown in red.
**Click the diagram to open it full size.** See the [full architecture reference](../reference/architecture.md) for the deep dive.*

| Layer | Resources |
|-------|-----------|
| Edge | Azure API Management (subscription-key auth, rate limiting) |
| Compute | AKS cluster `aetherion-aks`, namespace `aetherion`: 6 microservices + in-cluster Redis cache |
| Data | Azure Database for PostgreSQL Flexible Server · in-cluster Redis cache |
| Observability | Application Insights `aetherion-appi` · Log Analytics `aetherion-law` · Azure Managed Grafana |
| Agent | Azure SRE Agent `aetherion-sre-agent` |

## 6. Confirm it's healthy, then start

When the script finishes it prints a **validation summary**. You're ready when it
reports a healthy, traffic-generating estate and the Operations Center loads with
all tiles green.

Re-run the check on its own at any time:

```powershell
./scripts/04-validate.ps1
```

[Start Challenge 1 →](../challenges/01-onboard-and-baseline.md){ .md-button .md-button--primary }

---

<details markdown="1"><summary>What each component is for (reference)</summary>

| Component | Purpose | Where |
|-----------|---------|-------|
| Operations Center GUI | Live service health, risk gauge, flight map, incidents, business impact | `https://sreagenthack-XXXXX.<region>.cloudapp.azure.com/` |
| API front door | Partner/mobile entry point, subscription-key auth, rate limiting | `<apim-gateway-url>/aetherion/api/status` |
| PostgreSQL database | System of record for bookings, crews, and telemetry writes | Azure Database for PostgreSQL Flexible Server |
| Redis cache | Low-latency cache for booking/check-in read patterns | In-cluster `redis` container in AKS |
| Dashboards | Metrics, traces, log visualizations | Azure Managed Grafana |
| App telemetry | Requests, dependencies, exceptions, app map | Application Insights `aetherion-appi` |
| Logs | Container and node logs/metrics | Log Analytics `aetherion-law` |
| Compute | All microservices | AKS `aetherion-aks`, namespace `aetherion` |
| Load generator | Produces synthetic traffic during the workshop | Azure Container Instance in a separate resource group (not monitored by the agent) |
| Change history | Resource and deployment changes | Azure Activity Log + GitHub repo |
| Azure SRE Agent | Investigate, plan, and remediate with approval or bounded autonomy | Azure portal → `aetherion-sre-agent` |

Microservices: `gateway`, `flight-ops`, `crew-scheduling`, `booking`, `baggage`,
`telemetry-ingest`. Synthetic workshop traffic is generated externally by the load
generator (see the table above).

</details>

