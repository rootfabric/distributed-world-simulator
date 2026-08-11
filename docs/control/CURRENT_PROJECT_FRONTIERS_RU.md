# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1` with directional watched-dependency hardening  
**Purpose:** one-page operational map answering what is active, what may continue now, what checkpoint is next, and what blocks the following stage.

> This file is a human-facing snapshot. Machine operational truth remains `config/control/project-program-registry.v1.json`. If the two differ, the registry wins and this file must be refreshed.

---

## 1. Current operating rule

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
AUDITORS CHECK CONSISTENCY
GLOBAL ARCHITECTURE DEFINES OWNERSHIP AND INVARIANTS
```

For a new major runtime stage, default to:

```text
accepted evidence
      +
then-current canonical main
      ↓
fresh registered frontier
      ↓
minimal implementation
      ↓
focused validation
      ↓
full regression
      ↓
composition / merge / handoff
```

Do not continue an old accepted stacked lineage by default.

---

## 2. Active and tracked frontiers

| Program | Branch | Current state | What may be done now | Next checkpoint | Gate after checkpoint |
|---|---|---|---|---|---|
| **G** | `feature/g8-geomorphology` | G8.6 automated accepted, graphical pending | Run manual graphical acceptance only; no new runtime | **G8.6 ACCEPTED**, then **G8 Full Acceptance** | Freeze G8; **G9 waits for canonical R3 + MAT0** |
| **T** | `feature/t1b-composition-failure-recovery` | T1B.0–T1B.4 accepted handoff | No new T1B work | **HANDOFF COMPLETE** already reached | Resume at **T2.0** only after C22 integration + TS0.4 + PC0 convergence |
| **TS / C22** | `feature/c22-incremental-local-rebuild` | Source accepted, current-main refresh required | Build fresh current-main C22 convergence and retest | **SOURCE_ACCEPTED_MERGE_READY** on refreshed exact head | Explicit merge → post-merge PC0 → **MAIN_INTEGRATED** → TS0.4 |
| **CH** | `feature/ch9-6-playable-network-equipment-lab` | Windows automated accepted, graphical pending | Run two-pass graphical/recovery acceptance only | **CH9.6 ACCEPTED** | Post-acceptance PC0; later CH major work starts from current main/convergence base |
| **NX** | `feature/nx-m7-owner-authority-convergence` | NX.C0 clean preparation; legacy N frozen as evidence | PC0 hardening is now canonical; create fresh current-main **NX.C1** and implement minimal owner-authority slice | **NX.C1 IMPLEMENTED_CANDIDATE**, then validation → **NX SOURCE_ACCEPTED** | Exact-Windows focused/full/two-client/impaired-network/reconnect/dependency gates |
| **R3** | `feature/global-p0-r3-architecture` | Architecture candidate; refresh required | Refresh R3 change-set on current main and implement revision-transition rule | **R3 REFRESHED CANDIDATE / PC0 NON-RED** | Promote canonical R3, then Wave A from one SHA |
| **DOCTRINE** | `feature/world-building-doctrine` | Active design reference | Update only from new gameplay/system evidence | next doctrine alignment checkpoint | Must not acquire technical foundation ownership |
| **MATTER** | — | MW10 stable accepted foundation | No new branch unless a registered composition need appears | future GM/Geo-Matter gate | Keep Matter truth canonical |
| **S1** | — | stable proposal-only distributed compute | No new branch until a concrete workload needs it | workload-specific registered frontier | Workers remain proposal-only; authority commits |

---

## 3. Work that can proceed in parallel now

After PC0 directional-watch hardening became canonical in `main`, these tracks are independent enough to proceed in parallel:

```text
A. G8.6 manual graphical acceptance
B. CH9.6 two-pass graphical/recovery acceptance
C. C22 current-main convergence refresh + revalidation
D. fresh current-main NX.C1 minimal runtime transfer
E. R3 current-main refresh + revision-transition control rule
```

They must still run `CONTROL_PROJECT.ps1` at their declared control gates. Directional watched-dependency findings may require targeted revalidation of another program.

---

## 4. G — exact continuation

Current evidence:

```text
stage:   G8.6 Geomorphology Visual Lab
status:  AUTOMATED_ACCEPTED_MANUAL_GRAPHICAL_PENDING
tested:  a9ca1f8b723e4edc5ebff40db26e41283d464597
```

Do now:

```text
G     source/resolved changes visibly; Truth hash stable
1..7  all semantic views meaningful
W/S   LOD/stride/grid changes; canonical samples=561 and hash stay stable
X     PX/PZ seam has no crack/discontinuity
F     river overlay agrees with channel/bank/floodplain shape
```

Checkpoint sequence:

```text
manual PASS
  ↓
G8.6 ACCEPTED
  ↓
G8 Full Acceptance
  ↓
PC0
  ↓
G8 frozen as accepted evidence
```

Stop rule:

```text
DO NOT START G9
until canonical R3 + MAT0 MaterialDefinitionId exists
```

---

## 5. CH — exact continuation

Current evidence:

```text
stage:         CH9.6 Playable Network Equipment Lab
runtime:       7b2269b39952b8201714a7078a62b8f97057325c
tested head:   4cdafddce7cd6b5fa7ff45a06ae00f06320464ab
status:        WINDOWS_AUTOMATED_ACCEPTED_GRAPHICAL_PENDING
```

Do now on the preserved tested checkout:

```text
Run 1 with ResetState
  READY
  equip upper/lower/feet through real Inventory UI
  visual equipment appears only after canonical/server path
  unequip removes presentation
  movement/jump/crouch work
  close normally

Run 2 without ResetState
  equipment restores before new drag
  post-recovery unequip removes presentation
```

Checkpoint sequence:

```text
manual PASS
  ↓
CH9.6 ACCEPTED
  ↓
post-acceptance PC0
  ↓
freeze playable equipment vertical slice
```

Do not create CH9.7 merely to avoid the graphical gate.

---

## 6. Construction / C22 / TS / T — exact train

### C22 current-main refresh

The original C22 implementation stays accepted evidence. The next implementation branch must be current-main based.

Transfer/reproduce only the accepted production capability and related tests/validation. Do not import stale control-plane copies.

Checkpoint sequence:

```text
fresh current-main C22 convergence
  ↓
production-diff semantic equivalence
  ↓
C22 incremental focused PASS
C22 graphical PASS
C24 contracts PASS
  ↓
full world/core regression PASS
  ↓
SOURCE_ACCEPTED_MERGE_READY
  ↓ explicit merge authorization
C22 merged to main
  ↓
post-merge PC0
  ↓
MAIN_INTEGRATED
```

### TS0.4

Only after C22 `MAIN_INTEGRATED`, create fresh main-based:

```text
TS0.4 — 1M Research Ceiling
```

Measure at minimum:

```text
build / ingest time
incremental rebuild time
memory
artifact count and cache reuse
far-shell cost
streaming / representation cost
hot sections
main-thread budget
```

Classify honestly:

```text
PASSABLE
DEGRADED
CURRENT_CEILING_EXCEEDED
```

The goal is a trustworthy ceiling and bottleneck telemetry, not forcing one million objects to pass at any cost.

### T2.0 activation

Start `T2.0 — Real Heterogeneous Base / Station` only after:

```text
C22 MAIN_INTEGRATED
+
accepted T1A.7/T1B scale/composition evidence
+
TS0.4 classification
+
PC0 convergence
```

T2.0 must be a real heterogeneous construct, not another uniform cube-only benchmark. It should combine structural parts, doors/airlocks, generators, dependency networks, interactive fixtures, local rebuild, persistence/recovery, reconnect, interest and derived C22 representation.

T1B has no T1B.5.

---

## 7. NX — exact continuation

PC0 directional-watch hardening is now in canonical `main`, so the old NX.C0 gate is cleared.

Next action:

```text
create fresh NX.C1 from then-current main
```

Transfer/reimplement only:

```text
MovementAuthorityProfile
owner movement service
client/server locomotion composition
remote snapshot interpolation presentation
same-revision optimistic item rollback
```

Never transfer as production design:

```text
legacy FIX ladder
render _process() writing CharacterBody3D transform
unbounded relative client_tick scheduler
```

When runtime is introduced, NX health becomes YELLOW until validation finishes.

Required checkpoint gates:

```text
editor import
owner-authority focused
render/physics single-writer
item rollback/drop/pickup
client_tick fuzz if touched
full world/core regression
two-client process
LOCAL movement + items
impaired network
reconnect / ownership_epoch
directional dependency revalidation
```

Target checkpoint:

```text
NX SOURCE_ACCEPTED
```

Legacy `feature/m7-sequence-aware-...` remains evidence only and must not be directly merged.

---

## 8. GLOBAL-P0 R3 — exact continuation

R3 remains the intended next architecture revision, but the old candidate ancestry is not a promotion base.

Do now:

```text
refresh R3 change-set on current main
update machine frontier guards
implement R2 -> R3 revision-transition policy in PC0
run ownership/intersection review
require PC0 non-RED
```

Revision-transition categories:

```text
ACTIVE_NEW_RUNTIME_FRONTIER
  must use canonical R3 after promotion

FROZEN_ACCEPTED_EVIDENCE
  may remain R2 evidence-only

CONVERGENCE_FRONTIER
  must adopt R3 before adding new post-promotion runtime
```

Target checkpoint:

```text
GLOBAL-P0-2026-08-11-R3 canonical
```

Only then create, from one exact R3 SHA:

```text
IAM0/IAM1
MAT0
WT0
WQ0/WQ1
```

No Wave A branch may start from a different architecture base.

---

## 9. Immediate stop gates

Do not do any of the following without first changing the main-owned control/architecture state:

```text
T1B.5
G9 before canonical R3/MAT0
CH9.7 to bypass graphical acceptance
legacy N direct merge
legacy FIX7 render/physics writes
NX.C1 from stale/non-main base
TS0.4 before C22 MAIN_INTEGRATED
T2.0 before TS0.4 classification + PC0 convergence
R3 direct promotion from stale candidate ancestry
Wave A from different architecture bases
new global Registry/Manager/Authority/Material/Transaction/Query foundation in a domain branch
```

---

## 10. Checkpoint discipline

For every active program:

```text
implementation or manual gate
  ↓
focused checkpoint
  ↓
CONTROL_PROJECT.ps1
  ↓
full/composition checkpoint when required
  ↓
CONTROL_PROJECT.ps1
  ↓
frontier move is declared in main
```

No program may silently declare its own next global frontier only in branch-local docs.

`SOURCE_ACCEPTED`, `MAIN_INTEGRATED`, `COMPOSITION_VERIFIED`, and `PRODUCTION_READY` remain separate dimensions.

---

## 11. Canonical entry points

Start project-wide control from:

```text
PROJECT_CONTROL.md
```

Machine operational truth:

```text
config/control/project-program-registry.v1.json
```

This current one-page snapshot:

```text
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
```

Detailed current convergence plan:

```text
docs/plans/PROJECT_CONVERGENCE_2026-08-11_RU.md
```

Architecture constitution:

```text
docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
config/architecture/global-program-roadmap.v1.json
```

Run live control:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Read both standard and directional reports before opening any unregistered major frontier.
