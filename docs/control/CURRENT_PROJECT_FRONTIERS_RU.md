# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`

> Machine truth: `config/control/project-program-registry.v1.json`. This page is the human resolver, not an independent status ledger.

## Deterministic resolver

```text
CONTROL_PROJECT
      ↓
registry + this dashboard
      ↓
CURRENT PRIMARY
      ↓
EXECUTE_NOW if authorized
      │
      └─ otherwise PREPARE_NOW only
```

After every checkpoint, merge, promotion or unexpected `main` movement, fetch again and reread Project Control. Chat history is never authorization.

## Canonical milestone

C22 crossed the runtime merge boundary and passed mandatory post-merge control verification:

```text
H0.1 R8 / C22                         H0_1_PASS
C22 source state                      SOURCE_ACCEPTED_MERGE_READY
PR #90 merge                          WHOLE PR / NORMAL MERGE COMMIT
pre-merge main                        4a42c2fb6befb386f5c3eb48d9ba070745e25bbb
PR #90 head                           ab674669b9a293d898e5ca5983b4918cc685d990
implementation / review target        4c69de50c8374112d82efee2fd6917c770b3eae0
C22 merge / canonical main anchor     eefd75fa3badec10c6e7db959e2a3992dba30f0e
post-C22 Project Control              run 31558679306 / SUCCESS
standard PC0                          YELLOW / NON_RED
directional PC0                       YELLOW / NON_RED
critical cross-branch overlap         0
C22 critical directional hits         0
C22 state                             MAIN_INTEGRATED
H0.1 runtime slot                     RELEASED
```

The merge commit tree is exactly the accepted PR-head tree `10c92456537efca220a0d9ae242a58f5dbfd2b74`; `4c69de50...` remains an ancestor of canonical `main`. Merge therefore changed history/provenance, not the accepted runtime/test tree. The required new post-merge Project Control proof was executed on the merge commit and remained NON_RED.

## CURRENT PRIMARY

```text
C22 MAIN_INTEGRATED
        ↓
GLOBAL-P0 R3 exact-current-main refresh/final verification
        ↓
CRITICAL Reviewer → Verifier → Director final-gate sequence
        ↓
R3_REFRESHED_CANDIDATE_READY
        ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION
```

`GLOBAL_ARCHITECTURE_PROMOTION` is a separate CRITICAL human gate. No agent may cross it automatically.

## EXECUTE_NOW

Only architecture/control finalization of existing R3 preparation is on the critical path:

```text
fresh exact main + registry generation
        ↓
repin/rebase PR #85 candidate
        ↓
refresh ephemeral main/frontier guards
        ↓
R2 → R3 transition audit
        ↓
standard + directional PC0
        ↓
ownership/intersection review
        ↓
fresh exact-head Evidence Map
        ↓
Independent Reviewer PASS
        ↓
Independent Verifier PASS
        ↓
Director final gate PASS
        ↓
R3_REFRESHED_CANDIDATE_READY
        ↓
STOP at HUMAN GLOBAL_ARCHITECTURE_PROMOTION
```

Required invariants:

```text
ITEM = stable canonical foundation
V0 = composition consumer, not truth owner
H0.3 = DEVELOPMENT Work-Order scheduler/control layer
H0.3 != game runtime scheduler / gameplay authority / game-time owner
ECO = advisory research, not economy or production scheduler
ECON = reserved future economy program
```

## Live reconciled secondary facts

### CH9.6

Live CH passport reports:

```text
FOCUSED_ACCEPTED_POST_PC0_NON_RED_FROZEN
implementation / focused / operator graphical:
e547ba52a440e72cc02c6bbe449edaf160bae7ab
```

Do not repeat graphical acceptance. No repository-local acceptance JSON is invented. `CH -> NX` remains a real watched dependency and must be freshly revalidated before future NX source acceptance.

### ECO

Live ECO passport has advanced beyond the old main snapshot:

```text
ECO.PH5-S1..S4                       ACCEPTED
ECO.PH                               RESEARCH COMPLETE
CURRENT research                     CONV0-A design requirements only
NEXT                                 CAL1
CONV0-B                              waits canonical R3/WQ/MAT/LIFE/WB contracts
production ECO                       deferred
```

ECO remains advisory/research and does not block unrelated mainline progression.

## PREPARE_NOW

Preparation may continue without runtime mutation:

```text
H0.2 / NX.C1 Work Order + HIGH-risk acceptance package
CH -> NX dependency revalidation plan
H0.3 development scheduler acceptance package
V0 preimplementation package
GEO-min / ITEM-min / NET-min contracts
V0-S0..S5 scenario/evidence design
ECO CONV0-A research/design contracts
```

These are preparation assets only and do not authorize runtime execution.

## BLOCKED_UNTIL_GATE

```text
NO H0.2 / NX.C1 runtime before canonical R3 + post-R3 PC0
NO H0.3 implementation before H0_2_PASS + NX SOURCE_ACCEPTED
NO V0 runtime before H0.3 acceptance
NO G9 before canonical R3 + MAT0
NO MAT0 runtime before its canonical post-R3 dispatch
NO T2.0 before C22 MAIN_INTEGRATED + TS0.4 ceiling evidence + PC0 convergence
NO TS0.4 runtime before canonical R3 + post-R3 PC0 on this critical-path policy
NO production ECO convergence without a fresh Harness-controlled production frontier
```

Status dimensions remain independent:

```text
SOURCE_ACCEPTED != MAIN_INTEGRATED != COMPOSITION_VERIFIED != PRODUCTION_READY
```

And architecture remains:

```text
CANONICAL WORLD != PRESENTATION != TRANSPORT != COMPUTE
identity != LOD
feature != cell
spatial location != authority route
authority ownership != compute assignment
transport semantics != gameplay semantics
procedural baseline != mutable world state
representation artifact != canonical state
```
