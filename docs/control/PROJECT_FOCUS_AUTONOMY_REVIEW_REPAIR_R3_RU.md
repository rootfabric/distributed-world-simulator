# PROJECT-FOCUS — AUTONOMY REVIEW REPAIR R3

**Subject predecessor:** `719a89611a5cb376ee6bf80476587399af7b9a4e`
**Parent PR:** `#547`
**Role:** Implementer repair; этот документ не является Reviewer/Verifier verdict.

## Required findings

Fresh exact-head review `5121095739` на `719a896...` зафиксировал три P1:

- `3940491129` — непустой `proof_evidence_path` принимался как durable hard-block proof без Git/event/Work Order provenance;
- `3940491138` — synthetic autonomy test обходил production `build_state`, поэтому реальный `Drive` не получал hard-block proof;
- `3940491144` — SHA-256 reuse contract был декларативным: review loader и guarded transitions принимали raw `PASS` без machine-readable provenance.

## Bounded repair

1. Вводится canonical `hard-block-proof.schema.v1.json`. Final authoritative `BLOCKED` event должен явно ссылаться на proof в своём execution `evidence/`. `build_state` проверяет schema, Work Order/checkpoint/event identity, tracked/clean Git blob и существование того же blob не позднее commit-а, добавившего BLOCKED event. Только после этого добавляется derived `_durable_provenance_validated=true`, недоступный внешнему JSON.
2. `build_state -> continuation -> CLI Drive` получает только такой validated proof. Непустой выдуманный path, позднее добавленный proof и поздний rewrite не могут завершить mission как `HARD_BLOCKED`.
3. Для fresh post-build PASS после autonomy activation review loader machine-enforces `machine_evidence`: fresh re-execution связывает exact HEAD/TREE + runner/run; reuse дополнительно требует SHA-256-or-stronger manifest с artifact identity. Missing/unbound provenance даёт effective `INSUFFICIENT_EVIDENCE`. Те же правила применяются в event transition guards, поэтому raw PASS не обходит loader.
4. Historical review records, добавленные до autonomy activation, остаются replay-compatible; immutable historical executions/evidence не изменяются.

## Regression plan

- policy/runtime unit regressions;
- production-route fixture `ledger -> build_state -> CLI Drive`;
- negative checks: missing/retroactively-added/rewritten hard-block proof;
- review loader + guarded transition tests для fresh/reused/malformed provenance;
- полный `tests/harness` discovery;
- exact candidate Project Control после публикации.

## Non-goals

Не изменять runtime/scenes/P7 implementation, historical executions/acceptance, project ownership, P7 acceptance или MVP activation. Merge `#547` остаётся human gate после fresh Reviewer + fresh Verifier.
