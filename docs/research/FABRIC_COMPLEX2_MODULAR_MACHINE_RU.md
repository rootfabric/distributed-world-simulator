# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** 🟡 COMPLEX2 OPEN / ✅ A EXACT / ✅ B EXACT / ✅ C EXACT  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534  
**Predecessor:** `COMPLEX1B` ✅ CLOSED @ `50574d70a9f7abd5d21e54ab09755a567656f554`

## Текущая лестница

```text
COMPLEX1B mixed powered E2E              ✅ CLOSED
        ↓
COMPLEX2-A Modular Composition           ✅ EXACT VERIFIED
        ↓
COMPLEX2-B Compliant / Spring Response   ✅ EXACT VERIFIED
        ↓
COMPLEX2-C Articulated + Rotating Motion ✅ EXACT VERIFIED
        ↓
COMPLEX2-D Independent Structural Failure ← NEXT
        ↓
COMPLEX2-E Settle → Rebake → Re-impact
        ↓
COMPLEX2-PERF 500 / 1000 / 2000
        ↓
COMPLEX2-CLOSE
```

## Общая машина

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

Closed BRIDGE-2 R1 остаётся неизменным и содержит ровно один owner каждого representation kind:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

25 logical modules размещаются поверх этих пяти execution partitions; complexity объекта не создаёт competing canonical writers.

Logical composition:

```text
FRAME modules 0..7
DYNAMIC modules 8..11
  shoulder / elbow / shaft / carriage
FULL modules 12..14
CONTACT modules 15..18
HYBRID modules 19..24
  compliant module 20
  detachable module 24
```

Каждый module содержит 80 canonical parts: `25 × 80 = 2000`.

# COMPLEX2-A — Modular Composition

**Статус:** ✅ EXACT VERIFIED

```text
code subject 8d10a4e00b616c28e62cd16b4645342dc8256632
TREE         7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4
```

Evidence:

```text
validation/FABRIC_COMPLEX2_A_EXACT_EVIDENCE.md
```

A доказал:

```text
normal mixed movement == FULL
local CONTACT event
detach module 24
HYBRID-only invalidation/rebuild
support loss -> functional branch A OFF
FULL <-> HYBRID representation swap
second distinct support event
DYNAMIC-only invalidation/rebuild
functional branch B OFF
second-event lifecycle on already reconfigured machine
```

Acceptance:

```text
FABRIC COMPLEX2 Modular Machine Acceptance: PASS (2115 assertions)
```

Deterministic hash:

```text
7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

Visual:

```text
res://scenes/labs/fabric/complex2_modular_machine_lab.tscn
```

# COMPLEX2-B — Compliant / Spring Response

**Статус:** ✅ EXACT VERIFIED

Physical implementation:

```text
b1f4338b273f0889486553b18bea93d39127bba6
TREE 697a226e0eadc76803d5e70d10549931a5f8cfc6
```

Final verification:

```text
57204de250cd05af76dbff4a42827a983d056ebb
TREE 475d8d66a89b677da4ec131cc9595844bab244b8
```

Evidence:

```text
validation/FABRIC_COMPLEX2_B_COMPLIANT_RESPONSE_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2B_COMPLIANT_RESPONSE_RU.md
```

B расширяет существующий HYBRID owner для `module/complex2-20`:

```text
80 canonical spring/damper fibers
        ↓ coherent projection
1 reduced Kelvin-Voigt state q
```

Exact parameters:

```text
K = 720 N/m
C = 116 N*s/m
max FULL/HYBRID delta = 4.996003610813204e-16
max energy residual = 0
```

Fail-closed boundaries:

```text
COMPLEX2B_REFINEMENT_REQUIRED_FORCE
COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION
COMPLEX2B_COHERENT_MODE_VIOLATION
```

Acceptance:

```text
FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (65 assertions)
```

Visual:

```text
res://scenes/labs/fabric/complex2b_compliant_response_lab.tscn
```

# COMPLEX2-C — Articulated + Rotating Coupled Motion

**Статус:** ✅ EXACT VERIFIED

Exact executable subject:

```text
bfc9109a240b513dd6866da04bcad3fd8de4b275
TREE 1a676742b30179967ab7fe5ad4084a3b5cb42b75
```

Evidence:

```text
validation/FABRIC_COMPLEX2_C_COUPLED_MOTION_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2C_COUPLED_MOTION_RU.md
```

## Coupled physical state

Existing moving modules 8..11 become one reciprocal mechanical assembly:

```text
shoulder angle
      ↕
elbow angle
      ↕
shaft rotation
      ↕
carriage translation
```

Native angular/translational coordinates are converted into a common generalized path space. State:

```text
q[4] + v[4] = 8 physical states
```

Canonical reciprocal links:

```text
shoulder <-> elbow
elbow    <-> shaft
shaft    <-> carriage
shoulder <-> carriage  frame closure
```

DYNAMIC_ROM compiles dense `M/K/C`; FULL reference rebuilds the matrices from canonical coupling records every step.

## Exact motion equivalence

Implicit-midpoint integration is used so the discrete energy identity can be checked directly.

Measured exact result:

```text
max ACTIVE/FULL trajectory delta = 0
max energy balance residual = 5.273559366969494e-16 J
minimum damping dissipation >= 0
release energy monotonic = true
```

Certified native peaks:

```text
shoulder  0.2304349697 rad
elbow     0.2198972800 rad
shaft     0.7201419706 rad
carriage  0.0696275307 m
```

## Causal coupling falsifier

Shoulder-only force, all downstream direct forces zero:

```text
with reciprocal couplings:
shaft peak     0.0467785669 m path coordinate
carriage peak  0.0464149146 m

same subject with couplings removed:
shaft peak     0
carriage peak  0
```

Таким образом downstream motion действительно передаётся через mechanical coupling graph.

## Mid-motion representation transition

Evaluator меняется при ненулевых velocities/energy:

```text
step 150  DYNAMIC_ROM -> FULL
step 230  FULL -> DYNAMIC_ROM
```

Physical q/v state packet:

```text
handoff errors = [0, 0]
```

BRIDGE-2 representation swap events также выполняются дважды:

```text
representation ledger = 2
BRIDGE-2 swap handoff error = 0
mixed/FULL runtime delta = 0
final five-kind representation arrangement restored
```

COMPLEX2-B HYBRID compliant backend остаётся неизменным через весь C lifecycle.

## C fail-closed envelope

```text
non-reciprocal coupling
-> COMPLEX2C_NONRECIPROCAL_COUPLING

over-force
-> COMPLEX2C_REFINEMENT_REQUIRED_FORCE

out-of-range articulation
-> COMPLEX2C_REFINEMENT_REQUIRED_NATIVE_RANGE

out-of-range speed
-> COMPLEX2C_REFINEMENT_REQUIRED_SPEED

corrupt q/v handoff packet
-> COMPLEX2C_STATE_PACKET_CHECKSUM_MISMATCH
```

Exact acceptance, два independent exact runs:

```text
FABRIC COMPLEX2-C Coupled Motion Acceptance: PASS (66 assertions)
COMPLEX2C_EXPERIMENT_HASH=433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
```

Visual:

```text
res://scenes/labs/fabric/complex2c_coupled_motion_lab.tscn
```

Project Control на exact C subject: SUCCESS.

# Что ещё нужно для COMPLEX2 CLOSED

Следующие checkpoints:

1. **COMPLEX2-D — Independent Structural Support Failure**;
2. **COMPLEX2-E — Settle → Rebake → Re-impact Lifecycle**;
3. **COMPLEX2-PERF — 500 / 1000 / 2000 scaling matrix**;
4. **COMPLEX2-CLOSE — final exact closure review**.

`FABRIC0.19` остаётся **NOT AUTHORIZED**: A, B и C выражаются существующими topology/event, reconstruction/artifact и mixed-representation contracts плюс nested physical backends; нового generic foundation primitive пока не потребовалось.
