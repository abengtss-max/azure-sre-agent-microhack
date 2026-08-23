# Prerequisites

Install these tools before you run the environment setup.

## 1. Required tools

| Tool | Minimum version | Notes |
|------|-----------------|-------|
| PowerShell | 7.0 | required |
| Azure CLI | 2.60 | required |
| kubectl | any recent | required |
| Git | any recent | required |
| GitHub CLI (`gh`) | any recent | optional, but the setup and Challenge 8 steps give `gh` one-liners, and the Challenge 8 grader uses it to confirm the RCA issue and pull request instead of asking you |

## 2. Install on Windows (winget)

```powershell
winget install --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements
winget install --id Microsoft.AzureCLI --exact --accept-source-agreements --accept-package-agreements
winget install --id Kubernetes.kubectl --exact --accept-source-agreements --accept-package-agreements
winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements
winget install --id GitHub.cli --exact --accept-source-agreements --accept-package-agreements
```

After installing, restart your terminal so the commands are available on PATH.
Sign in to the GitHub CLI once with `gh auth login`.

!!! warning "Run every command in PowerShell 7 (`pwsh`)"
    Windows PowerShell 5.1 is the default on Windows and is **not** supported: the
    scripts stop with a version error. Start your session with `pwsh` and confirm
    with `$PSVersionTable.PSVersion` (must be 7.0 or later).

## 3. A GitHub account, and a token you can actually create

You need a GitHub account to create your own copy of the application repository
(it is a **template repo**, so this is one click). Challenge 8 also has the agent
write back to that copy — it files the incident RCA as an issue and opens a pull
request — and for that it needs a credential of its own.

| What | When it's needed | How you supply it |
|---|---|---|
| GitHub account | Setup — **Use this template** on the app repo | Sign in |
| GitHub **Connector** | Challenge 8 Task 5 — file the RCA as an issue | OAuth browser popup, **or** a fine-grained PAT |
| GitHub **MCP server** | Challenge 8 Task 6 — branch, commit, open a PR | **Personal Access Token only** — there is no OAuth option |

!!! warning "Create the token on day one, not at Challenge 8"
    Create it now, or confirm you are able to. It needs, on your copy:

    - **Contents: Read and write** — create a branch and commit to it
    - **Pull requests: Read and write** — open the PR
    - **Issues: Read and write** — file the RCA

    A classic token with `repo` scope also works. A token with read-only access
    **connects successfully and then fails on the first write**, which reads like a
    broken connector rather than a permissions problem.

    Create the repo under your **personal account**. In an organisation a
    fine-grained token can additionally require **owner approval**, which is not
    instant, and discovering that at Challenge 8 costs you the day.

Continue to [Set up the environment](environment.md).
