# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** 🟡 COMPLEX2 OPEN / ✅ COMPLEX2-A EXACT VERIFIED / ✅ COMPLEX2-B EXACT VERIFIED  
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
COMPLEX2-C Articulated + Rotating Motion ← NEXT
        ↓
COMPLEX2-D Structural Failure
        ↓
COMPLEX2-E Settle → Rebake → Re-impact
        ↓
COMPLEX2-PERF
        ↓
COMPLEX2-CLOSE
```

## Цель COMPLEX2

COMPLEX2 повышает сложность одновременной композицией структурных, динамических, контактных, compliant и functional подсистем, а не простым ростом visual node count.

Базовая машина:

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

Closed BRIDGE-2 R1 остаётся неизменным и содержит ровно по одному owner каждого representation kind:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

25 logical modules размещаются поверх этих пяти execution partitions. Рост complexity не создаёт 25 competing physical authority owners.

## Logical machine

```text
FRAME modules 0..7
  ↓
DYNAMIC drive modules 8..11
  ├─ arm shoulder
  ├─ arm elbow
  ├─ rotating shaft
  └─ translating carriage
  ↓
FULL articulated/impact modules 12..14
  ↓
CONTACT tooling modules 15..18
  ↓
HYBRID compliant/detachable modules 19..24
  ├─ compliant module 20
  └─ detachable head module 24
```

Каждый module содержит ровно 80 canonical parts: `25 × 80 = 2000`.

# COMPLEX2-A — Modular Composition

**Статус:** ✅ EXACT VERIFIED

Exact code subject:

```text
8d10a4e00b616c28e62cd16b4645342dc8256632
TREE 7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4
```

Evidence:

```text
validation/FABRIC_COMPLEX2_A_EXACT_EVIDENCE.md
```

## Functional composition

Generic conservation FABRIC из COMPLEX1A используется без machine-specific electrical solver:

```text
source/battery
  ├─ wire/branch-a -> load A
  │       supported by support/complex2-23-24
  │
  └─ wire/branch-b -> load B
          supported by support/complex2-10-11
```

Exact causal result:

```text
baseline             A ON   B ON
module 24 detached   A OFF  B ON
second support loss  A OFF  B OFF
```

Обе functional mutations имеют reason `SUPPORT_TOPOLOGY_LOST`.

## A executable sequence

```text
normal mixed movement == FULL reference
        ↓
local CONTACT event
        ↓
detach module 24
        ↓
HYBRID only STALE → rebuild, handoff=0
        ↓
load A OFF / load B ON
        ↓
FULL ↔ HYBRID_BAKE representation swap, handoff=0
        ↓
second distinct support event on reconfigured machine
        ↓
DYNAMIC only STALE → rebuild, handoff=0
        ↓
load B OFF
        ↓
mixed execution resumes == FULL reference
```

Deterministic exact hash from independent processes:

```text
7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

Acceptance:

```text
FABRIC COMPLEX2 Modular Machine Acceptance: PASS (2115 assertions)
```

Visual scene:

```text
res://scenes/labs/fabric/complex2_modular_machine_lab.tscn
```

# COMPLEX2-B — Compliant / Spring Response Envelope

**Статус:** ✅ EXACT VERIFIED

Physical implementation subject:

```text
b1f4338b273f0889486553b18bea93d39127bba6
TREE 697a226e0eadc76803d5e70d10549931a5f8cfc6
```

Final verification subject:

```text
57204de250cd05af76dbff4a42827a983d056ebb
TREE 475d8d66a89b677da4ec131cc9595844bab244b8
```

Evidence:

```text
validation/FABRIC_COMPLEX2_B_COMPLIANT_RESPONSE_EXACT_EVIDENCE.md
```

Detailed design:

```text
docs/research/FABRIC_COMPLEX2B_COMPLIANT_RESPONSE_RU.md
```

## Compliance ownership

COMPLEX2-B не создаёт новый physical owner. Он расширяет backend существующего `region/complex2-hybrid` для `module/complex2-20`:

```text
80 canonical compliant part states
80 canonical spring/damper fibers
        ↓ coherent projection
1 reduced HYBRID compliance state q
```

BRIDGE-2 representation set остаётся ровно тем же five-kind set.

## Constitutive response

Kelvin-Voigt envelope:

```text
F = K q + C q_dot
```

Exact aggregate parameters:

```text
K = 720 N/m
C = 116 N*s/m
```

FULL reference каждый step суммирует все 80 fibers; HYBRID reduced backend использует compiled aggregate parameters.

Exact equality:

```text
max |q_FULL - q_HYBRID| = 4.996003610813204e-16
required <= 1e-12
```

## Projection / reconstruction

Проверяется:

```text
FULL(80) → reduced(1) → FULL(80)
```

через существующие:

```text
BakeStateMapping
ReconstructionDescriptor
PhysicalBakeArtifact
```

Projection, reconstruction и handoff bounds находятся внутри `1e-12`.

## Energy / release

Exact response:

```text
peak |q|  = 0.095426442 m
final |q| = 0.004284087 m
max energy balance residual = 0
```

После release stored energy монотонно уменьшается, damper dissipates positive energy и section возвращается близко к neutral state.

## Fail-closed refinement

Reduced coherent model запрещено применять вне certified envelope:

```text
COMPLEX2B_REFINEMENT_REQUIRED_FORCE
COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION
COMPLEX2B_COHERENT_MODE_VIOLATION
```

Это создаёт executable boundary для будущего adaptive fidelity без преждевременного изменения foundation semantics.

## B exact result

Acceptance на final exact source:

```text
FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (65 assertions)
full=80 reduced=1
Kelvin-Voigt energy=PASS
guards=PASS
scene=PASS
extended=FULL_REFERENCE
```

Integrated hash двух независимых exact invocations:

```text
af5779bddc65a504c9ec14612b3dc62341032e4ed770a885c2df679dcbcd6795
```

Visual scene:

```text
res://scenes/labs/fabric/complex2b_compliant_response_lab.tscn
```

Project Control на final B verification subject: SUCCESS.

# Что ещё нужно для COMPLEX2 CLOSED

Следующие checkpoints:

1. **COMPLEX2-C — Articulated + Rotating Coupled Motion**;
2. **COMPLEX2-D — Independent Structural Support Failure**;
3. **COMPLEX2-E — Settle → Rebake → Re-impact Lifecycle**;
4. **COMPLEX2-PERF — 500 / 1000 / 2000 scaling matrix**;
5. **COMPLEX2-CLOSE — final exact closure review**.

`FABRIC0.19` остаётся **NOT AUTHORIZED**: COMPLEX2-A и COMPLEX2-B пока выражаются существующими FLOW/JUMP/topology, reconstruction, artifact и mixed-representation contracts без нового generic foundation primitive.
