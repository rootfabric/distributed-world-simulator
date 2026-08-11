# GLOBAL-P0 R3 Refresh R1 — checkpoint progress

**Target checkpoint:** `R3_REFRESHED_CANDIDATE`  
**Candidate:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Base:** `main @ 1112d1f7cfad1df18fb3621a537e191e674848c6`  
**Registry:** `75`  
**Risk:** `CRITICAL`  
**Promotion:** `NOT AUTHORIZED`

## Current disposition

This branch is a fresh current-main reconstruction of the old GLOBAL-P0 R3 architecture proposal. It carries architecture/control/docs only and must stop before canonical promotion.

The active H0.1 R6 C22 pilot is deliberately treated as an R2 runtime checkpoint. R3 promotion must wait for its checkpoint boundary or explicitly invalidate/refresh that work.

## Checkpoint predicates

| Predicate | State | Evidence |
|---|---|---|
| `CURRENT_MAIN_REFRESH` | **PASS** | branch created from exact `1112d1f7`; registry 75 |
| `CRITICAL_RISK_CLASSIFIED` | **PASS** | candidate + passport classify architecture revision as CRITICAL |
| `DESIGN_BRIEF_READY` | **PASS** | machine candidate contains problem/current/desired/design/non-goals/validation |
| `FRONTIER_GUARDS_REFRESHED` | **PASS** | guards reflect H0.0 canonical, H0.1 R6, G8 frozen, T1B handoff, C22 source evidence, NX.C0 wait, ECO PH3/PH3C |
| `R2_TO_R3_TRANSITION_POLICY_IMPLEMENTED` | **PASS** | `config/control/global-p0-r2-to-r3-transition-policy.v1.json` |
| `OWNERSHIP_INTERSECTION_REVIEW_PASS` | PENDING | independent review required |
| `EVIDENCE_MAP_COMPLETE` | PENDING | build after review/freshness validation |
| `REVIEWER_VERDICT_PASS` | PENDING | independent CRITICAL reviewer |
| `PC0_NON_RED` | PENDING | run on Draft PR exact head |
| `HUMAN_ATTENTION_ITEM_PREPARED_IF_DECISION_REQUIRED` | NOT REQUIRED YET | required at promotion decision, not during candidate construction |

## Important correction from old R3

Old candidate used `ECO` as economy. Current project already owns `ECO` as Evolutionary Ecology.

Fresh R3 defines:

```text
ECO   Evolutionary Ecology
ECON  future World Economy / Markets / Contracts
```

This avoids a program/ownership collision before architecture promotion.

## No-runtime scope

Allowed candidate surfaces:

```text
config/architecture/global-p0-r3-architecture-candidate.v1.json
config/control/architecture-ownership-r3-candidate.v1.json
config/control/global-p0-r2-to-r3-transition-policy.v1.json
config/control/branches/control__global-p0-r3-refresh-r1.v1.json
docs/architecture/GLOBAL_P0_R3_ARCHITECTURE_CANDIDATE_RU.md
docs/plans/GLOBAL_P0_R3_PARALLEL_IMPLEMENTATION_PLAN_RU.md
docs/checkpoints/2026-08-12_GLOBAL_P0_R3_REFRESH_R1_RU.md
```

No gameplay/runtime/domain implementation is authorized.

## Next bounded step

1. Open Draft PR against current main.
2. Run Project Control and require NON_RED.
3. Perform independent ownership/intersection review, explicitly checking H0/HARNESS vs WB/OPS and ECO vs ECON naming/ownership.
4. Build exact-head Evidence Map.
5. Perform independent CRITICAL reviewer/verifier pass.
6. If all gates pass, propose `R3_REFRESHED_CANDIDATE` and stop.

Do **not** perform `GLOBAL_ARCHITECTURE_PROMOTION` in this branch without a separate explicit human authorization and a safe H0.1 runtime boundary.
