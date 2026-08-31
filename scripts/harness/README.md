# Restart-safe checkpoint-session control scaffold

`CONTROL_DEVELOPMENT.ps1` is the only public entry point. It supports exactly
one of `-Status`, `-Plan`, `-Resume`, `-Drive`, `-CloseRole`, `-CloseMission`,
or `-Close`; `-Execute` remains deliberately rejected. `-Close` is an alias of
`-CloseMission` because the user-visible session is the checkpoint mission,
not the current isolated role.

The script is PowerShell 5.1 compatible, anchors paths at `$PSScriptRoot`,
prints readable stage lines first, and leaves one UTF-8 JSON envelope as its
final output line.

Without `-Execution`, the Harness resolves the active checkpoint from
machine-owned scheduler policy and then selects the newest matching durable
execution. `-Checkpoint` selects another declared checkpoint. `-Execution`
exists as an exact diagnostic/recovery override and must match `-Checkpoint`
when both are supplied. No mutable execution path is hard-coded in the public
entry point.

The envelope schema is
`validation/harness/control-development-output.schema.v1.json`. Stable failure
codes remain `2 INVALID_INVOCATION`, `3 CONTRACT_OR_DEPENDENCY_INVALID`,
`4 GIT_STATE_INVALID`, `5 EXECUTION_STATE_INVALID`, and `6 INTERNAL_ERROR`.
Checkpoint-session close gates add `7 ROLE_EXIT_FORBIDDEN` and
`8 MISSION_EXIT_FORBIDDEN`.

`-Drive` is the parent-session continuation command. It derives one of:

```text
CONTINUE_REQUIRED
MISSION_COMPLETE
WAITING_HUMAN
HARD_BLOCKED
```

For `CONTINUE_REQUIRED`, execute the returned `next_actor` / `next_action` in
the required isolated role context, persist its durable result, and run
`-Drive` again in the same parent checkpoint session. Reviewer and Verifier
independence is preserved; only the user-visible session remains continuous.

`role_exit_allowed` and `mission_exit_allowed` are separate. A routine
`ROLE_BOUNDARY` may allow the child role to end while the checkpoint mission
remains open. `session_exit_allowed` is retained as a compatibility alias for
`mission_exit_allowed`.

Successful mission completion is fail-closed: local `IMPLEMENTED`, `VERIFIED`,
`AUDITED`, or `CHECKPOINT_PROPOSED` states do not complete a mission. The
success terminal requires a durable canonical-main `ACCEPTED` record for the
exact goal checkpoint. `WAITING_HUMAN` is allowed only for a declared blocking
human decision. `BLOCKED` alone is non-terminal; a hard stop requires durable
proof that the blocker is non-automatable in current scope.

Append-only execution events remain authoritative. The Work Order `state` is a
derived snapshot and a mismatch still fails with
`WORK_ORDER_SNAPSHOT_STATE_MISMATCH`. Main movement continues to block normal
execution unless the existing epoch/audit rules permit it.

No command installs dependencies or bypasses runtime-branch, review, PC0,
merge, or architecture gates. Install the pinned dependency from
`scripts/harness/requirements.txt`, then run:

```text
python -m unittest discover -s tests/harness -v
```

## Default Git write authority

An active checkpoint mission is project-preauthorized for routine Git operations through `A3_INTEGRATE_CANDIDATE`: scoped branch/worktree creation, scoped staging, commit, non-force push, durable evidence publication, draft PR creation/update and independent-review request. These operations are not Harness Human Attention gates and must not trigger a repeated user permission prompt.

Merge, direct push to canonical `main`, force-push/history rewrite, destructive remote branch deletion and architecture/foundation authority changes remain explicit human gates. If the hosting/tool platform imposes a separate confirmation requirement, report `EXTERNAL_TOOL_AUTH_REQUIRED`; do not reinterpret it as a project-level Harness gate.


## Terminal reporting and local execution

Every continuation result includes a machine-derived `terminal_report`. A
user-visible final response may say `FINISHED` only when
`mission_complete=true`. Non-terminal `CONTINUE_REQUIRED` returns
`final_response_allowed=false`.

When the current environment cannot execute a required local step, create a
schema-valid committed OPEN handoff under
`config/control/harness/executions/<execution>/handoffs/`. The handoff must
bind the exact implementation head and contain executable commands, PASS/FAIL
criteria, evidence destination, and resume behavior. Only then may
`LOCAL_EXECUTION_REQUIRED` authorize mission-session exit. The separate
local-agent instruction is rendered from this Git-owned handoff; chat-only
handoffs are invalid.
