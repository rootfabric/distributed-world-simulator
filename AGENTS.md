# Distributed World Simulator — Agent Router

Root `AGENTS.md` is a routing layer, not an independent roadmap or architecture source.

## Mandatory read order

Before changing code, creating a branch, fixing a defect, reviewing a PR or declaring a checkpoint, read:

```text
PROJECT_CONTROL.md
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
docs/control/HARNESS_AUTONOMOUS_EXECUTION_RU.md
docs/control/HARNESS_CHANNEL_RECOVERY_RU.md
config/control/project-program-registry.v1.json
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
```

Then read the active program passport, nearest scoped `AGENTS.md` / local guidance, and relevant validation/checkpoint evidence. If historical/local prose conflicts with the main-owned registry, PC0, Harness policy or architecture ownership, the central main-owned control state wins.

## Hard rules

```text
MAIN DECLARES PROJECT STATE
BRANCHES REPORT EXECUTION FACTS
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
GIT IS DURABLE MEMORY; CHAT IS NOT
EPHEMERAL TOOL HANDLES ARE CACHE; DURABLE LOCATORS ARE AUTHORITY
TOOL / TRANSPORT / SESSION FAILURE IS NOT A MISSION TERMINAL
EXECUTOR-LOCAL NETWORK FAILURE IS A ROUTE FAILURE, NOT A PROJECT BLOCK
RECOVER FROM EXACT SHA / DURABLE LOCATOR, NOT FROM STALE RESOURCE IDS
IMPLEMENTER CANNOT SELF-ACCEPT
CHECKPOINT IS THE UNIT OF CONTROL
CHECKPOINT MISSION IS THE USER SESSION UNIT
WORK ORDER IS THE EXECUTION UNIT
ROLE IS THE ISOLATION UNIT
ROLE BOUNDARY IS NOT A MISSION BOUNDARY
EVIDENCE PACKAGE IS THE UNIT OF REVIEW
EXCEPTION IS THE UNIT OF HUMAN ATTENTION
HUMAN IS NOT A ROUTINE RESULT COURIER
ACTIVE CHECKPOINT MISSION PRE-AUTHORIZES ROUTINE A0-A3 GIT OPERATIONS
DO NOT ASK FOR BRANCH / COMMIT / NON-FORCE-PUSH / DRAFT-PR CONFIRMATION
GIT AUTHORITY SURVIVES ROUTINE ROLE BOUNDARIES
SELF-EXECUTE AVAILABLE AUTOMATABLE WORK BEFORE HANDOFF
PREFERRED EXECUTOR UNAVAILABLE IS NOT A HARD BLOCK
VERIFIER INDEPENDENCE DOES NOT REQUIRE A SPECIFIC VM PROVIDER
```

Scoped instructions may add local conventions, traps, launch commands and tests, but may not override architecture ownership, PC0 policy, main-owned registry, checkpoint catalog, risk minimums, review requirements, autonomy ceiling or human gates.

## Agent work protocol

For every checkpoint mission:

1. Resolve the active checkpoint and exact Project Epoch / base SHA from machine-owned state; do not use chat as authority.
2. Keep one parent user-visible session bound to that checkpoint until canonical acceptance, a genuine `WAITING_HUMAN`, or a proven non-automatable hard block.
3. Use bounded Work Orders for execution and isolated role contexts for Implementer / Reviewer / Verifier / Integrator / Director responsibilities.
4. Preserve separation of duties. A fresh Reviewer/Verifier role may end after its durable handoff, but the parent checkpoint mission remains open.
5. Continue `PLANNED`, `DISPATCHED`, `IN_PROGRESS`, implementer-owned validation and automatable `FIX_REQUIRED` work instead of reporting an unfinished stop.
6. On `FIX_REQUIRED`, follow Repair Doctrine, run focused validation and required regressions, then route a fresh exact-head review/verification as required.
7. Persist every role result to the declared durable evidence sink. A chat-only PASS/FAIL does not complete a handoff.
8. Run `CONTROL_DEVELOPMENT.ps1 -Drive` after every durable role result. The returned `next_actor` / `next_action` is the next child role inside the same parent mission.
9. Before ending an isolated role, `CONTROL_DEVELOPMENT.ps1 -CloseRole` must authorize it. Exit code `7` means continue the role.
10. Before the final user response, `CONTROL_DEVELOPMENT.ps1 -Close` (alias of `-CloseMission`) must authorize mission exit. Exit code `8` means the checkpoint mission is still open and must continue.
11. Run PC0 and directional audit before checkpoint proposal/acceptance as required by the Work Order.
12. Routine Git operations inside the active checkpoint mission and bounded Work Order are already authorized through the default `A3_INTEGRATE_CANDIDATE` ceiling. Do not re-ask for permission to create a feature/control/repair branch, stage scoped paths, commit, non-force push, post durable evidence, open/update a draft PR, or request independent review.
13. A Director may create and durably publish a bounded repair continuation Work Order inside the same checkpoint mission without a new approval when scope/authority is not expanded.
14. Ask a human only for an actual declared decision/approval such as merge, force-push/history rewrite, direct push to canonical main, architecture/foundation authority change, or another explicit Human Attention gate; never use the human to copy results between routine roles.
15. If an external platform/tool refuses a Git write until it receives its own confirmation, classify that as `EXTERNAL_TOOL_AUTH_REQUIRED`, not as a Harness human gate.
16. Execute all available mechanical work yourself before handoff: local/VM tests, clean exact checkout, repository-owned CI, artifact/log collection, scoped repair/retest and append-only evidence publication. These are routine A0-A3 operations.
17. If a preferred executor (including a Codex Cloud environment) is unavailable, follow `HARNESS_AUTONOMOUS_EXECUTION_RU.md` and try the next allowed executor. Do not declare `HARD_BLOCKED` until all allowed automated fallbacks and scope-preserving recovery are exhausted and durably proven.
18. Keep role independence separate from machine ownership: Implementer may produce exact machine evidence but cannot issue its own independent verdict. A fresh Reviewer/Verifier may consume trusted exact-head evidence without a separate VM rerun unless the Work Order/risk contract explicitly requires independent execution.
19. Treat `ResourceNotReadable`, `Resource not found`, expired result handles and similar tool-resource failures as ephemeral cache loss. Discard the stale handle, refetch by durable repository/ref/path/run/artifact locator, verify exact subject identity and resume from the last durable predicate.
20. Treat `Could not resolve host`, ad-hoc clone failure, download security rejection and equivalent executor-local network/transport failures as route failures. Do not infer GitHub/project outage and do not repeat the same failed route; switch to the GitHub connector, an existing exact checkout, repository-owned CI or the next allowed executor.
21. Before a long/high-fanout tool phase, ensure a durable resume anchor exists (exact subject, last completed predicate, next action, recovery route). After any substantial channel failure, re-anchor the exact HEAD/subject before continuing; stale resource ids never cross a recovery boundary.
22. Never end a non-terminal checkpoint mission merely because the current tool/session channel became unreliable. Follow `HARNESS_CHANNEL_RECOVERY_RU.md`, fail forward from durable Git state, and only stop at `MISSION_COMPLETE`, genuine `HUMAN_DECISION_REQUIRED`, or fully proven `HARD_BLOCKED`.

## Checkpoint-session control surface

Для понимания проекта сначала используйте `-Overview`: он читает один канонический
срез целей и семейств работ без загрузки execution. `-CheckConsistency` проверяет
продуктовую согласованность; family-local findings не являются неявным MVP gate.
`-Candidate` допустим только с этими двумя режимами и никогда не разрешает dispatch.
Цели и последовательность: `docs/plans/PROJECT_DEVELOPMENT_FOCUS_RU.md`.
Рекомендации research tracks не заменяют Work Order или main-owned activation.

```text
.\CONTROL_DEVELOPMENT.ps1 -Status
.\CONTROL_DEVELOPMENT.ps1 -Overview
.\CONTROL_DEVELOPMENT.ps1 -CheckConsistency
.\CONTROL_DEVELOPMENT.ps1 -Plan
.\CONTROL_DEVELOPMENT.ps1 -Resume
.\CONTROL_DEVELOPMENT.ps1 -Drive
.\CONTROL_DEVELOPMENT.ps1 -CloseRole
.\CONTROL_DEVELOPMENT.ps1 -Close
```

`-Drive` resolves the current product checkpoint from scheduler policy unless `-Checkpoint` or exact diagnostic `-Execution` is supplied. `-Close` is intentionally the mission gate, not the current-role gate.

## Default Git authority

An active checkpoint mission carries project-level Git write authority up to the default autonomy ceiling `A3_INTEGRATE_CANDIDATE`. `allowed_paths` / Work Order scope is the write fence; role changes do not revoke that authority.

```text
PREAUTHORIZED WITHOUT NEW HUMAN PROMPT:
branch/worktree creation
scoped stage
commit
non-force push
passport/evidence publication
PR comment/evidence publication
open/update draft PR
request independent review
checkpoint proposal

HUMAN GATE:
merge
direct push to canonical main
force-push / history rewrite
destructive remote branch deletion
architecture/foundation authority change
explicit product decision gate
```

## Language and commits

- Project documentation and user-facing development reports: Russian.
- Code identifiers, schemas, error codes and commit types: English.
- Use Conventional Commits for normal development commits.
- Do not force-push active Harness-managed branches.

## Godot runtime / MCP

Before giving a human local launch/test command on Windows or Ubuntu, read `docs/GODOT_LOCAL_TESTING_RU.md` and use its canonical workspace layout, double-Godot paths, fresh-worktree import rule and OS-specific command form.

If work requires autonomous Godot launch, runtime input, screenshots or runtime logs, also read `docs/MCP_GODOT.md` before the first runtime action and follow that contract. Runtime evidence must use the project-approved Godot/MCP path rather than ad-hoc desktop observation when machine capture is available.

## Bounded control-repair closure

For PROJECT-FOCUS autonomy repair, read `docs/control/PROJECT_FOCUS_AUTONOMY_REPAIR_R3_RU.md`.
Reproduce each required finding through the production entry point; a synthetic state
or policy-only assertion is not sufficient coverage. Freeze a tested implementation
HEAD before fresh review and publish later evidence separately. Do not expand that
subject with unrelated Harness improvements. After two identical infrastructure
failures change the permitted execution strategy, not the acceptance criterion.
Never describe queued work or an external role request as continuing background work.
