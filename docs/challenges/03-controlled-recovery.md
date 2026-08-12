# Challenge 3 · Controlled Recovery and Change Correlation

!!! abstract "Challenge 03 of 08 · Act II: Human-Guided Operations"
    **Run mode:** Review → approved write · **Access:** scoped write on approval

    **Stage:** Foundation → **Operations** → Engineering → Autonomous → Major Incident

**Situation.** Two things hit in quick succession. Your check-in hypothesis is solid
and the director wants it fixed **safely**, with a human in the loop. Then the live
**flight board** goes dark for every station and `flight-ops` drops straight to red,
the hallmark of a bad change. The flight board is the picture the whole center flies
by, so this is a **P1**: restore first, then correlate the change to prevent
recurrence.

**Mission.** Recover check-in with the least-disruptive action under human approval,
then restore the flight board by correlating the outage with a recent change and
applying a reversible rollback, and verifying both from telemetry.

**Why this matters**

<div class="grid cards why-cards" markdown>

- :material-account-check-outline: **Human-in-the-loop**: approve the least-disruptive write
- :material-backup-restore: **Reversible recovery**: roll back to the last good state
- :material-source-branch: **Change correlation**: line the outage up with a deploy or commit
- :material-check-decagram-outline: **Verified from telemetry**: prove recovery, don't assume it

</div>

!!! example "Start this challenge"

    ```powershell
    ./scripts/start-challenge.ps1 3   # open the incident
    ```

### Tasks

1. **Plan the fix.** Ask the agent to turn your hypothesis into a concrete `booking` remediation plan and name the permission it needs.
2. **Recover under approval.** Apply the least-disruptive fix with your approval (on-behalf-of, or a narrow scoped role), then confirm latency is back to baseline.
3. **Triage the flight board.** Find out how `flight-ops` is failing from pod status and events.
4. **Correlate and roll back.** Line the outage up with the recent change, apply a reversible rollback, and check the board recovers.

![Challenge 3 storyboard: Sam, Aria and Elena run a controlled recovery and correlate the change](../assets/storyboard/img-challenge-3.webp){ .story-panel loading=lazy }

### Suggested Azure SRE Agent prompt

!!! quote "Paste into the agent chat"
    Turn my check-in hypothesis into a concrete remediation plan for the `booking`
    service that removes the added latency without rebuilding, and tell me exactly
    what permission the action needs. Then, for `flight-ops`, correlate the outage
    time with recent deployment/rollout history and the GitHub change record, and
    propose the least-disruptive **reversible** rollback for my approval.

### Success criteria

- Check-in is remediated with a least-disruptive action governed by approval or a scoped role (not ungoverned automation); `booking` is healthy and latency is back to baseline.
- `flight-ops`'s failure mode is identified and linked to a recent change/rollout; the recovery is reversible and doesn't touch unrelated resources.
- Both tiles are green, `/api/flights` responds, and `check-challenge.ps1 3` passes.

!!! success "Verify your work"

    Run this when you're done. It grades the real end state:

    ```powershell
    ./scripts/check-challenge.ps1 3
    ```

### Hints

<details markdown="1"><summary>Hint: recover check-in safely</summary>

Ask the agent for a remediation *plan* first. It tells you the permission the
action needs. The safe fix removes the added delay and leaves the autoscaler to
absorb the surge; it shouldn't touch the database, Redis, or nodes.
</details>

<details markdown="1"><summary>Hint: restore the flight board</summary>

Confirm how `flight-ops` is failing in AKS first, then line up the moment the tile
went red with deployment / rollout history and the repo's recent changes. Closeness
in time is your strongest lead, and returning to the last good state is usually the
fix.
</details>

!!! question "Stuck? Step-by-step for each task"
    Give each task a genuine attempt first, and skim the hints above. When you want
    the exact clicks, open the matching task below.

    ??? note "Task 1 · Plan the fix"
        - In the agent chat, paste the **suggested prompt** above (or ask it to turn
          your check-in hypothesis into a concrete `booking` remediation plan).
        - The plan is your **approval artifact**: it should say exactly what it will
          change and the **permission** the action needs.

    ??? note "Task 2 · Recover under approval"
        Apply the least-disruptive fix one of two governed ways:

        - **On-behalf-of:** keep the agent in **Review**, and select **Approve** when
          it proposes the write; it runs once, with your permission.
        - **Scoped role:** grant the agent's managed identity a **narrow** write role
          on just the affected resource (portal → resource group → **Access control
          (IAM)**), then let it act with its own identity.

        Then verify `booking` latency is back to baseline.

    ??? note "Task 3 · Triage the flight board"
        - Check `flight-ops` pod status and recent events:
          `kubectl get pods -n aetherion -l app=flight-ops` and
          `kubectl describe deploy/flight-ops -n aetherion`.
        - Decide the failure mode (crash-looping, failed probe, bad image) before you
          change anything.

    ??? note "Task 4 · Correlate and roll back"
        - Line the outage time up with **deployment / rollout history** and the repo's
          recent changes: `kubectl rollout history deploy/flight-ops -n aetherion`,
          plus your fork's commits.
        - Apply a **reversible** rollback to the last good revision (for example
          `kubectl rollout undo deploy/flight-ops -n aetherion`), then confirm the
          board updates and `/api/flights` responds.

### Reference

- [Review and approve mitigations](https://learn.microsoft.com/en-us/azure/sre-agent/execute-mitigations)
- [Manage roles and permissions](https://learn.microsoft.com/en-us/azure/sre-agent/manage-permissions)
- [Connect source code](https://learn.microsoft.com/en-us/azure/sre-agent/connect-source-code)

!!! success "Up next: teach the agent your runbooks"
    The next incident's fix is already written in Aetherion's runbooks, if only the agent knew them.

    [Proceed to Challenge 4 · Ground the Agent →](04-ground-the-agent.md){ .md-button .md-button--primary }

---
