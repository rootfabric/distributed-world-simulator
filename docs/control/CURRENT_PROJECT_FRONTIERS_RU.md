# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`  
**Review layer:** `H0-REVIEW-2026-08-11-R1`

> Human-facing snapshot. Machine operational truth is `config/control/project-program-registry.v1.json`; if they differ, the registry wins.

---

## 1. Current operating rule

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
RISK ROUTES REVIEW DEPTH
EVIDENCE MAP IS THE REVIEW UNIT
EXCEPTION IS THE HUMAN ATTENTION UNIT
```

New runtime work does not continue old stacked lineage by default:

```text
accepted evidence
      +
then-current canonical main
      ↓
Project Epoch
      ↓
bounded Work Order
      ↓
risk/design gate
      ↓
implementation
      ↓
validation + Evidence Map + independent review
      ↓
PC0 / composition
      ↓
checkpoint proposal
```

---

## 2. Active and tracked frontiers

| Program | Current state | What may be done now | Next checkpoint | Gate after checkpoint |
|---|---|---|---|---|
| **HARNESS** | H0.0 planned; canonical contracts ready | Implement **control-only** Status/Plan/Resume, reducer, contract loader, epoch validator, Git-only recovery fixtures | **H0_0_SCAFFOLD_READY** | Then H0.1/C22 becomes first autonomous runtime pilot |
| **G** | G8.6 automated accepted, graphical pending | Manual graphical acceptance only | **G8.6 ACCEPTED**, then **G8 Full Acceptance** | Freeze G8; G9 waits canonical R3 + MAT0 |
| **T** | T1B.0–T1B.4 accepted handoff | No new T1B work | HANDOFF COMPLETE already reached | Resume at T2.0 after C22 + TS0.4 + PC0 |
| **TS / C22** | Accepted evidence; waiting H0.0 before fresh convergence | No autonomous C22 runtime yet | After H0.0: **H0.1 + C22 SOURCE_ACCEPTED_MERGE_READY** | Explicit runtime merge → PC0 → MAIN_INTEGRATED → TS0.4 |
| **CH** | Windows automated accepted, graphical pending | Two-pass graphical/recovery acceptance | **CH9.6 ACCEPTED** | Post-acceptance PC0; freeze slice |
| **NX** | NX.C0 preparation complete; runtime waiting H0.1 | Analysis/evidence only; do not start NX.C1 runtime | After H0.1: H0.2/NX → **NX SOURCE_ACCEPTED** | HIGH-risk evidence/review + network/reconnect gates |
| **R3** | Architecture candidate; refresh required | Analysis/current-main refresh may proceed; **no promotion** | **R3 REFRESHED CANDIDATE / PC0 NON-RED** | CRITICAL review + human promotion gate |
| **DOCTRINE** | Active design reference | Update only from new gameplay/system evidence | next doctrine alignment checkpoint | Must not own technical foundations |
| **MATTER** | MW10 stable accepted | No new branch without registered composition need | future GM/Geo-Matter gate | Keep Matter truth canonical |
| **S1** | Stable proposal-only compute | No new branch until concrete workload | workload-specific frontier | Workers remain proposal-only |

---

## 3. What can proceed in parallel now

```text
A. H0.0 restart-safe harness scaffold (control-only)
B. G8.6 manual graphical acceptance
C. CH9.6 manual graphical/recovery acceptance
D. R3 current-main analysis/refresh without promotion
```

Explicitly **not yet allowed**:

```text
C22 autonomous runtime convergence  → waits H0_0_SCAFFOLD_READY
NX.C1 runtime                        → waits H0.1 PASS
multiple autonomous runtime workers → waits H0.3
```

This intentionally slows runtime branching for one checkpoint so the development control loop becomes restart-safe before scaling agent concurrency.

---

## 4. HARNESS — immediate critical path

### H0.0 — Restart-Safe Harness Scaffold

Nearest project-wide checkpoint:

```text
H0_0_SCAFFOLD_READY
```

Implement from then-current canonical `main`:

```text
CONTROL_DEVELOPMENT.ps1
-Status
-Plan
-Resume

state/event reducer
contract/schema loader
Project Epoch validator + invalidation detection
Git-only recovery fixtures
review/evidence contract loading
```

Required properties:

```text
NO runtime branch creation
NO gameplay/domain changes
state reconstructs without chat
review/evidence contracts parse/load
PC0 non-RED
```

Only after H0.0 is accepted and integrated may H0.1 create the fresh C22 runtime branch.

### H0.1 — C22 Closed Loop

H0.1 must prove not only tests, but the full evidence-driven flow:

```text
risk classification
Design Brief when required
fresh current-main C22 branch
bounded capability transfer
focused + graphical + C24 + full regression
post-build critique
Evidence Map
independent Reviewer verdict PASS
exact fresh review/test heads
PC0 + directional PC0
Human Attention Queue empty/resolved
clean-session recovery drill
Draft PR
STOP before merge
```

Target:

```text
H0_1_PASS
+
C22 SOURCE_ACCEPTED_MERGE_READY
```

---

## 5. Risk/review routing

```text
LOW      → Implementer + Verifier
MEDIUM   → Implementer + Reviewer + Verifier
HIGH     → Implementer + Reviewer + Verifier + Director
CRITICAL → Implementer + Reviewer + Verifier + Director + Human
```

Mandatory review rules for runtime checkpoints:

```text
Evidence Map complete
Reviewer verdict = PASS
INSUFFICIENT_EVIDENCE blocks checkpoint
reviewed HEAD == evidence HEAD == tested runtime HEAD for runtime scope
FIX_REQUIRED on MEDIUM+ → Repair Map before next non-trivial fix
```

Human attention is exception-driven; commit count is never the control interface.

---

## 6. G — exact continuation

Tested automated head:

```text
a9ca1f8b723e4edc5ebff40db26e41283d464597
```

Manual checks:

```text
G     source/resolved changes; Truth hash stable
1..7  semantic views meaningful
W/S   LOD/stride/grid changes; canonical samples=561 and hash stable
X     PX/PZ seam has no crack
F     river overlay coherent with channel/bank/floodplain
```

Sequence:

```text
manual PASS → G8.6 ACCEPTED → G8 Full Acceptance → PC0 → freeze G8
```

Do not start G9 before canonical R3 + MAT0.

---

## 7. CH — exact continuation

Preserved tested head:

```text
4cdafddce7cd6b5fa7ff45a06ae00f06320464ab
```

Run 1 with ResetState: equip/unequip through real Inventory UI, verify presentation, movement/jump/crouch, normal close.

Run 2 without ResetState: durable equipment restores before new drag; post-recovery unequip removes presentation.

Sequence:

```text
manual PASS → CH9.6 ACCEPTED → post-acceptance PC0 → freeze slice
```

Do not create CH9.7 to bypass the gate.

---

## 8. Construction train

```text
H0_0_SCAFFOLD_READY
        ↓
H0.1 fresh C22 convergence
        ↓
C22 SOURCE_ACCEPTED_MERGE_READY
        ↓ human runtime merge authorization
C22 MAIN_INTEGRATED
        ↓
TS0.4 1M Research Ceiling
        ↓
classification: PASSABLE / DEGRADED / CURRENT_CEILING_EXCEEDED
        ↓
PC0 convergence with accepted T evidence
        ↓
T2.0 Real Heterogeneous Base / Station
```

T1B has no T1B.5.

---

## 9. NX train

NX runtime is intentionally held until H0.1 proves the closed loop.

Then NX becomes H0.2 and has minimum HIGH risk because it touches authority/protocol/recovery behavior.

Authorized capability remains minimal:

```text
MovementAuthorityProfile
owner movement service
client/server locomotion composition
remote snapshot interpolation presentation
same-revision optimistic item rollback
```

Never transfer:

```text
legacy FIX ladder
render _process() writing CharacterBody3D transform
unbounded relative client_tick scheduler
```

NX acceptance additionally requires Evidence Map, independent review and exact-head freshness on top of focused/full/two-client/impaired-network/reconnect/dependency gates.

---

## 10. R3 train

R3 may be refreshed/analyzed in parallel but promotion remains a CRITICAL risk/human gate.

Required candidate path:

```text
current-main refresh
CRITICAL risk classification
Design Brief
frontier guards
R2→R3 transition policy
ownership/intersection review
Evidence Map
Reviewer PASS
PC0 non-RED
Human Attention item when architectural choice exists
```

Only human-approved canonical R3 may start IAM/MAT/WT/WQ Wave A from one exact SHA.

---

## 11. Immediate stop gates

```text
NO autonomous runtime before H0_0_SCAFFOLD_READY
NO NX.C1 runtime before H0.1 PASS
NO multiple autonomous runtime workers before H0.3
NO T1B.5
NO G9 before canonical R3 + MAT0
NO CH9.7 to bypass graphical gate
NO legacy N direct merge
NO FIX7 render/physics writes
NO TS0.4 before C22 MAIN_INTEGRATED
NO T2.0 before TS0.4 classification + PC0 convergence
NO R3 promotion without CRITICAL review + human approval
NO Wave A from divergent bases
NO new global Registry/Manager/Authority/Material/Transaction/Query foundation in a domain branch
```

---

## 12. Canonical entry points

```text
PROJECT_CONTROL.md
AGENTS.md
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
config/control/project-program-registry.v1.json
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
```

Live control:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

When H0.0 is implemented, development control adds:

```powershell
.\CONTROL_DEVELOPMENT.ps1 -Status
.\CONTROL_DEVELOPMENT.ps1 -Plan
.\CONTROL_DEVELOPMENT.ps1 -Resume
```
