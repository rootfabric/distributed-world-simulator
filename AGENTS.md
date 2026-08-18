# Distributed World Simulator — Agent Router

Root `AGENTS.md` is a routing layer, not an independent roadmap, architecture source or live project-state mirror.

## Cold start

Always establish authority first:

```text
PROJECT_CONTROL.md
HARNESS_CONTROL.md
config/control/project-program-registry.v1.json
```

Then route by the work being performed instead of loading every control document unconditionally.

```text
IMPLEMENT / FIX
  -> active program passport
  -> nearest scoped AGENTS.md / local guidance
  -> relevant tests and owner contracts

REVIEW / VERIFY
  -> docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
  -> config/control/harness/review-policy.v1.json
  -> exact Work Order / PR subject and durable evidence

CONTROL / CHECKPOINT / RECOVERY
  -> docs/control/DEVELOPMENT_HARNESS_RU.md
  -> config/control/harness/**
  -> relevant Project Control evidence

ARCHITECTURE / OWNERSHIP
  -> architecture ownership + program registry + PC0 contracts

GODOT RUNTIME / HUMAN LAUNCH
  -> docs/GODOT_LOCAL_TESTING_RU.md
  -> docs/MCP_GODOT.md when autonomous runtime evidence is required
```

Do not copy mutable current checkpoint, branch or frontier state into this router. Obtain live state from the main-owned machine contracts or `CONTROL_DEVELOPMENT.ps1 -Status/-Plan/-Resume`.

If historical/local prose conflicts with the main-owned registry, PC0, Harness policy or architecture ownership, the central main-owned control state wins.

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
ROUTINE ROLE HANDOFF IS NOT A HUMAN DECISION
HUMAN IS NOT A ROUTINE RESULT COURIER
MISSION REMAINS OPEN ACROSS ROLE BOUNDARIES
```

Scoped instructions may add local conventions, traps, launch commands and tests, but may not override architecture ownership, PC0 policy, main-owned registry, checkpoint catalog, risk minimums, review requirements, autonomy ceiling or human gates.

## Work protocol

For every Work Order:

1. Confirm exact Project Epoch / base SHA and current PC0 state.
2. Preserve the parent mission/objective; finishing one role does not finish the mission.
3. Stay inside allowed paths and explicit non-goals.
4. Classify risk using `config/control/harness/risk-policy.v1.json`.
5. For MEDIUM+ work, complete the Design Brief before implementation.
6. Commit/push durable recoverable states; do not use commit count as throughput.
7. On `FIX_REQUIRED`, follow Repair Doctrine before another non-trivial fix.
8. After MEDIUM+ implementation, perform one bounded post-build critique.
9. Use an independent Reviewer/Verifier according to risk routing.
10. Reviewer/Verifier results must be persisted to the declared durable evidence sink before a role transition can complete. A chat-only PASS is not evidence.
11. Treat missing proof as `INSUFFICIENT_EVIDENCE`, not an invitation to guess.
12. Ensure reviewed/evidence/tested heads are exact and fresh.
13. Run PC0 and directional audit before checkpoint proposal.
14. Ask a human only for an actual Human Attention decision/approval; never use the human as a message bus between routine roles.
15. At every stop report the machine-derived `next_actor`, `next_action`, `resume_condition` and whether the global mission is complete.

## Harness hygiene

Rules have a lifecycle. Prefer, in order:

```text
machine check -> template -> routed document -> short triggered rule -> explanation
```

Do not auto-delete safety/security/control/architecture invariants. When a prose rule becomes mechanically enforced, remove duplicate prose only through reviewed Harness hygiene work. Current policy and rule passports live in:

```text
config/control/harness/instruction-hygiene-policy.v1.json
config/control/harness/rule-registry.v1.json
```

## Language and commits

- Project documentation and user-facing development reports: Russian.
- Code identifiers, schemas, error codes and commit types: English.
- Use Conventional Commits for normal development commits.
- Do not force-push active Harness-managed branches.
