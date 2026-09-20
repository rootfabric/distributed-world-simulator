# FABRIC — Current Roadmap after HOLDOUT-R4 Audit

Дата: 20 сентября 2026.

## Неизменяемая история

```text
FABRIC0.18 / B0.x / BRIDGE-1..3       historical research closures preserved
COMPLEX3 5k/20k/100k                  RESEARCH EXACT CLOSED (bounded baseline)
HOLDOUT-R4 @ e6228a39...               ACCEPTED for bounded fixed-family unseen claim
PR #592                                OPEN / UNMERGED / separate human gate
```

Исторический R4 не отменяется. Его claim ограничен тем, что реально проверено: future-beacon параметры внутри заранее замороженных семейств transport / fixed 6-node electrical graph / fixed 5-node axial mechanics / fixed quartic event family, плюс G2 regressions и independent verifier.

## Актуальный путь

```text
historical HOLDOUT-R4 ACCEPTED
              │
              ▼
R4.1 NUMERIC + DIAGNOSTIC REPAIR        ✅ CLOSED
  - finite-output/fail-closed numeric envelope
  - stable PERF failure shape
  - no matrix_hash masking
  - unchanged G2 / PERF / CLOSE / B0.6 contracts
              │
              ▼
NEW SUBJECT FREEZE + fresh review/verifier
              │
              ▼
R4.2 TOPOLOGY + DYNAMIC HOLDOUT          ✅ CLOSED
  - multiple unseen topology families
  - variable node/port/active-DOF counts
  - near-singular + unsupported negatives
  - coupled dynamic trajectory
  - lifecycle/canonical-mutation/rebake continuation
  - preregistered future randomness
  - independent oracle
              │
              ▼
SCALE-R5 EXECUTABLE CAMPAIGN             ← CURRENT
  - axes: canonical N / active DOF k / boundary b / events / changed deps
  - metadata walks + hashes + solver + reconstruction + allocations + RSS/CPU
  - variable causal island, not hard-coded 20 FULL
  - local event and genuinely propagating/global control
  - 5k / 20k / 100k durable predicates
              │
              ▼
INTEGRATION-R6
  - fresh current-main consumer
  - minimal capability contract
  - fresh review/verifier
  - human merge gate
```

## Gate rules

- SCALE-R5 **design/instrumentation may proceed in parallel** with R4.1/R4.2.
- Large executable SCALE-R5 acceptance does not begin until R4.2 is closed on the repaired subject.
- Do not raise `MAX_NODES`, budgets or tolerances merely to obtain PASS.
- `COMPLEX3` is a baseline, not a future milestone to reimplement.
- New product mutations after `e622...` require a new subject and fresh evidence; historical Reviewer/Verifier freshness does not transfer.
- Old revealed R4 cases become regressions only; they can never be called unseen for the new subject.
- Safety/refinement may expand globally when causality requires it; locality is an observed property, not a forced outcome.

## Current acceptance target

`R4.1` и `R4.2` закрыты на frozen evidence. Следующий research stage — `SCALE-R5`: executable scaling campaign без изменения уже закрытых R4.1/R4.2 claims.
