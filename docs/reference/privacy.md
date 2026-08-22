# Privacy and browser storage

This workshop site is static documentation published on GitHub Pages. There is no
account to create, no server-side profile, no advertising and no third-party
analytics or tracking product. Nothing you do here is sent to us.

The one thing the site does keep is your **challenge progress**, and it keeps it in
your own browser using `localStorage` rather than cookies.

## What is stored

| Name | Category | Purpose | Retention | Set by |
|------|----------|---------|-----------|--------|
| `srehack:consent:v1` | Strictly necessary | Records the choice you made below, so you are not asked on every page | Until you clear it, or until the notice changes | This site |
| `srehack:progress:v1` | Functional | Which challenges you have marked complete, so the progress bar survives a reload | Until you clear it | This site |
| `srehack:seen-intro` | Functional | Whether you have dismissed the one-time "New here?" hint | Until you clear it | This site |
| `__palette` | Functional | Your light/dark preference, if you use the theme toggle | Until you clear it | Material for MkDocs theme |

The theme prefixes its own entry with the site path, so it appears in your browser
as something like `/azure-sre-agent-microhack/.__palette`.

Search is handled entirely in the browser by the theme and does not store a
search history.

## Your choice

Choosing **Reject non-essential** removes the functional entries above and stops
them being written again. The site remains fully usable: you can still read every
page, mark challenges complete and watch the progress bar fill — that state simply
lives in the current tab and is gone when you close it.

<button type="button" class="aet-consent-btn" data-aet-consent-open>Review or change your choice</button>

## Removing the data yourself

You do not need us to clear anything for you. Either use **Reject non-essential**
above, or clear site data for this domain in your browser: in Chrome or Edge,
**Developer tools → Application → Local storage**, then delete the entries listed
above. Private or incognito windows discard all of it automatically when closed.

If your browser blocks storage entirely, the site detects that and falls back to
keeping progress for the current tab only.

## The rest of the workshop

Everything you deploy during the hack — the AKS cluster, the database, the SRE
Agent and its threads — lives in **your own Azure subscription** and is governed by
your organisation's agreements with Microsoft, not by this page. The teardown
script removes it:

```powershell
./scripts/99-teardown.ps1
```
