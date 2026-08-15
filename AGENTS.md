# Distributed World Simulator — Agent Router

Root `AGENTS.md` is a routing layer, not an independent roadmap or architecture source.

## Mandatory read order

Before changing code, creating a branch, fixing a defect, reviewing a PR or declaring a checkpoint, read:

```text
PROJECT_CONTROL.md
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
config/control/project-program-registry.v1.json
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
```

Then read:

```text
active program passport
nearest scoped AGENTS.md / local guidance if present
relevant validation/checkpoint evidence
```

For any Windows local development, worktree, runtime, MCP or verification action, also read:

```text
docs/control/WINDOWS_LOCAL_WORKSPACE_RU.md
```

If any historical/local prose conflicts with the main-owned registry, PC0, harness policy or architecture ownership, the central main-owned control state wins.

## Hard rules

```text
MAIN DECLARES PROJECT STATE
BRANCHES REPORT EXECUTION FACTS
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
GIT IS DURABLE MEMORY; CHAT IS NOT
IMPLEMENTER CANNOT SELF-ACCEPT
CHECKPOINT IS THE UNIT OF CONTROL
EVIDENCE PACKAGE IS THE UNIT OF REVIEW
EXCEPTION IS THE UNIT OF HUMAN ATTENTION
```

Scoped instructions may add local conventions, traps, launch commands and tests, but may not override:

```text
architecture ownership
PC0 policy
main-owned registry
checkpoint catalog
risk minimums
review requirements
autonomy ceiling
human gates
```

## Agent work protocol

For every Work Order:

1. Confirm exact Project Epoch / base SHA and current PC0 state.
2. Stay inside allowed paths and explicit non-goals.
3. Classify risk using `config/control/harness/risk-policy.v1.json`.
4. For MEDIUM+ work, complete the Design Brief before implementation.
5. Commit/push durable recoverable states; do not use commit count as throughput.
6. On `FIX_REQUIRED`, follow Repair Doctrine before another non-trivial fix.
7. After MEDIUM+ implementation, perform one bounded post-build critique.
8. Produce the required Evidence Map.
9. Use an independent Reviewer/Verifier according to risk routing.
10. Treat missing proof as `INSUFFICIENT_EVIDENCE`, not an invitation to guess.
11. Ensure reviewed/evidence/tested heads are exact and fresh.
12. Run PC0 and directional audit before checkpoint proposal.
13. Surface only genuine human decisions through the Human Attention Queue.

## Current harness gate

```text
H0.0_SCAFFOLD_READY first
NO autonomous runtime worker before H0.0
H0.1 C22 only after H0.0
```

## Windows local workspace

The Windows filesystem contract is defined by `docs/control/WINDOWS_LOCAL_WORKSPACE_RU.md` and is mandatory for local Windows work.

Canonical locations:

```text
workspace root:
C:\distributed-world-simulator\

central checkout:
C:\distributed-world-simulator\distributed-world-simulator\

Godot tools only:
C:\Godot\godot\bin\

console executable:
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe

GUI executable:
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe
```

All new task worktrees, clean verification worktrees and temporary project checkouts on Windows MUST be direct children of `C:\distributed-world-simulator\`. Do not create repository worktrees under `C:\Godot\`; that tree is reserved for Godot tooling.

Historical examples using `C:\Godot\lunar-world-double-godot` or `C:\Godot\v0-*` are stale and MUST be translated to the canonical workspace contract before execution.

Repository launchers and test scripts should derive the active project root from the checkout/worktree they are executed from. A fixed Godot executable path is allowed; a fixed repository checkout path in reusable launchers is not.

## Language and commits

- Project documentation and user-facing development reports: Russian.
- Code identifiers, schemas, error codes and commit types: English.
- Use Conventional Commits for normal development commits.
- Do not force-push active harness-managed branches.

## Godot runtime / MCP

If work requires launching Godot, runtime input, screenshots or runtime logs, read `docs/control/WINDOWS_LOCAL_WORKSPACE_RU.md` first on Windows, then read `docs/MCP_GODOT.md` before the first runtime action and follow that contract. The Windows workspace contract owns filesystem locations and supersedes historical repository-path examples in older prose. Runtime evidence must use the project-approved Godot/MCP path rather than ad-hoc desktop observation when machine capture is available.