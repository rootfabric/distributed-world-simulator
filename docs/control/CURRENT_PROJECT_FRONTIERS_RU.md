# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`

> Human-facing snapshot. Machine truth is `config/control/project-program-registry.v1.json`.

## Project milestone

The project has reached the H0.0 convergence milestone:

```text
H0.0 verified checkpoint evidence     COMPLETE
G8 Full Acceptance                    COMPLETE / FROZEN
T1B aggregate handoff                 COMPLETE
MATTER / S1                           STABLE
```

The canonicalization candidate preserves the terminal H0.0 R3 evidence and switches the active development control surface to a fresh generation-70 **H0.1 planning epoch**.

```text
H0_0_SCAFFOLD_READY
        ↓ canonical control integration
H0.1 planning state
        ↓ post-merge main audit
        ↓ Director dispatch
fresh current-main C22 child Work Order
```

No C22 runtime branch is authorized merely by the H0.0 checkpoint merge.

## Live frontiers

| Program | Current state | What may happen next |
|---|---|---|
| **HARNESS** | H0.0 verified; H0.1 planning prepared | Canonicalize checkpoint, post-merge audit, Director-dispatch the C22 child Work Order |
| **G** | **G8 FULL ACCEPTED / FROZEN** | No G8 work. G9 waits canonical GLOBAL-P0 R3 + MAT0 |
| **T** | **T1B HANDOFF COMPLETE** | No T1B.5. T2.0 waits C22 integration + TS0.4 + PC0 |
| **TS/C22** | SOURCE_ACCEPTED evidence; fresh convergence pending | H0.1 will create a fresh current-main C22 convergence branch only after dispatch |
| **CH** | Windows automated accepted; graphical recovery gate pending | Finish two-pass manual CH9.6 observation; this does not block H0.1 |
| **NX** | NX.C0 preparation complete | Runtime NX.C1 waits H0.1 PASS |
| **ECO** | advisory research; P1C-S3 exact Windows pending | Continue independently; does not block mainline delivery |
| **GLOBAL-P0 R3** | architecture candidate; refresh required | Refresh/review in parallel; promotion remains CRITICAL + human gate |
| **DOCTRINE** | design reference | Update from new evidence only |
| **MATTER** | MW10 stable | No active frontier |
| **S1** | stable proposal-only compute | No active frontier |

## H0.0 evidence preserved

Terminal historical execution:

```text
E2026-08-11-H0-0-R3
Work Order: H0-0-R3-WO-001
implementation head: 8deffb80c3e445ef9b8d556d2a1fc2666abea8fc
terminal control head: 53533c8bb7d185b4617adcb2561cb322e5297e8e
state: CHECKPOINT_PROPOSED
```

Evidence includes:

```text
13 / 13 required predicates
Windows clean-clone focused suite PASS
Status / Plan / Resume PASS
Git-only recovery PASS
main-movement audit continuation PASS
Evidence Map PASS
Independent Reviewer PASS
Independent Verifier PASS
standard PC0 NON_RED
directional PC0 NON_RED
runtime_authorized = false
```

R3 execution identity is historical and must not be rewritten to follow later registry generations.

## Active canonical planning state

```text
E2026-08-11-H0-1-R1
base main: be6ea2a8636a9242fc808aea377d9144ef9bc9eb
registry generation: 70 candidate / generation-69 source base
checkpoint: H0_1_CLOSED_LOOP_C22_PILOT
Work Order: H0-1-R1-DISPATCH-WO-001
state: PLANNED
branch: main
```

The planning Work Order explicitly forbids runtime/domain paths. Before Director dispatch:

```text
autonomous_runtime_workers = 0
C22 branch creation = FORBIDDEN_UNTIL_DISPATCH
```

After actual canonical merge, main has moved relative to the epoch base by definition. H0 must therefore first record a post-merge NON_RED main audit. Only after that audit may the Director dispatch H0.1 and create the fresh C22 child Work Order/branch.

## G8 achievement

Live G passport records:

```text
G8.0 ACCEPTED
G8.1 ACCEPTED
G8.2 ACCEPTED
G8.3 ACCEPTED
G8.4 ACCEPTED
G8.5 ACCEPTED
G8.6 ACCEPTED
G8 FULL ACCEPTANCE
SOURCE_ACCEPTED_FROZEN_WAITING_R3_MAT0
```

Acceptance anchors:

```text
runtime automated: a9ca1f8b723e4edc5ebff40db26e41283d464597
manual graphical:  b91ed3eb8664ec1aee28453947a84c6a56acb95b
aggregate Windows: 31c0d4eef30544d4d5090b14721585047a97b979
```

Do not extend the frozen G8 branch into G9.

## T1B achievement

```text
T1B.0 ACCEPTED
T1B.1 ACCEPTED
T1B.2 ACCEPTED
T1B.3 ACCEPTED
T1B.4 ACCEPTED
T1B Aggregate HANDOFF COMPLETE
```

There is no T1B.5.

## Nonblocking unfinished work

These do not block the H0.0 project checkpoint:

```text
CH9.6 manual graphical/recovery observation
ECO.P1C-S3 exact-Windows research acceptance
GLOBAL-P0 R3 current-main refresh/promotion work
```

They remain governed by their own stop gates.

## Critical path after canonical checkpoint

```text
H0_0_SCAFFOLD_READY canonical
        ↓
post-merge H0.1 main audit
        ↓
Director dispatch
        ↓
fresh C22 convergence branch / child Work Order
        ↓
semantic production-diff equivalence
focused C22 + C24 contracts + graphical
full world/core regression
post-build critique
Evidence Map
independent review
standard + directional PC0
recovery drill
Draft PR
        ↓
H0_1_PASS + C22 SOURCE_ACCEPTED_MERGE_READY
        ↓ STOP / explicit runtime merge gate
```

NX.C1 remains blocked until H0.1 PASS. Multiple autonomous runtime workers remain blocked until H0.3.

## Immediate stop gates

```text
NO C22 runtime branch before post-merge H0.1 audit + Director dispatch
NO C22 runtime merge without explicit human authorization
NO NX.C1 runtime before H0.1 PASS
NO multiple runtime workers before H0.3
NO T1B.5
NO G9 before canonical R3 + MAT0
NO CH stage after CH9.6 before graphical acceptance + post-PC0
NO GLOBAL-P0 R3 promotion without CRITICAL review + human approval
NO ECO production promotion from research state without fresh controlled frontier
```

## Canonical entry points

```text
PROJECT_CONTROL.md
AGENTS.md
HARNESS_CONTROL.md
CONTROL_PROJECT.ps1
CONTROL_DEVELOPMENT.ps1
config/control/project-program-registry.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/scheduler-policy.v1.json
docs/checkpoints/2026-08-11_PROJECT_CHECKPOINT_READINESS_AUDIT_RU.md
```
