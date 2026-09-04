# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** 🟡 COMPLEX2 OPEN / ✅ COMPLEX2-A EXACT VERIFIED  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534  
**Predecessor:** `COMPLEX1B` ✅ CLOSED @ `50574d70a9f7abd5d21e54ab09755a567656f554`  
**Exact COMPLEX2-A code subject:** `8d10a4e00b616c28e62cd16b4645342dc8256632`  
**Exact TREE:** `7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4`  
**Evidence:** `validation/FABRIC_COMPLEX2_A_EXACT_EVIDENCE.md`

## Цель

COMPLEX2 повышает сложность одновременной композицией структурных, динамических, контактных и функциональных подсистем, а не простым увеличением visual node count.

Первый executable envelope уже реализован и exact-проверен:

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

## BRIDGE-2 R1 boundary

Closed BRIDGE-2 R1 требует ровно пять execution regions и ровно один owner каждого kind:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

COMPLEX2 не ослабляет этот контракт. 25 logical modules размещаются поверх пяти execution partitions. Рост canonical machine complexity не создаёт 25 competing physical authority owners.

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
  ├─ compliant carriage
  └─ detachable head module 24
```

Каждый module владеет ровно 80 canonical parts: `25 × 80 = 2000`.

## Functional composition

Используется generic conservation FABRIC из COMPLEX1A; machine-specific electrical solver не добавлялся.

```text
source/battery
  ├─ wire/branch-a -> load A
  │       supported by support/complex2-23-24
  │
  └─ wire/branch-b -> load B
          supported by support/complex2-10-11
```

Causal result exact-tested:

```text
baseline             A ON   B ON
module 24 detached   A OFF  B ON
second support loss  A OFF  B OFF
```

Обе functional mutations имеют reason `SUPPORT_TOPOLOGY_LOST`.

## COMPLEX2-A executable sequence

### Normal movement

Mixed runtime получает drive flow в DYNAMIC_ROM + HYBRID_BAKE. Все steps сравниваются с FULL reference.

```text
max |MIXED - FULL| = 0
required bound <= 1e-12
```

### Local contact

Contact flow маршрутизируется только через:

```text
region/complex2-contact
```

Contact state меняется, mixed outcome остаётся равен FULL.

### Detachable module

```text
event/complex2-detach-module-24
support/complex2-23-24
```

Результат:

```text
module 24 -> singleton component
module revision 100 -> 101
only HYBRID region invalidated
stale mixed execution forbidden
HYBRID rebuild handoff error = 0
wire/branch-a lost
load A OFF
load B stays ON
```

### Stabilization + representation swap

После rebuild и стабилизации один representation event атомарно меняет:

```text
region/complex2-full    FULL        -> HYBRID_BAKE
region/complex2-hybrid  HYBRID_BAKE -> FULL
```

```text
state handoff error = 0
representation ledger entries = 1
five-kind set preserved
```

### Second event on reconfigured machine

```text
event/complex2-break-drive-support
support/complex2-10-11
```

Результат:

```text
module revision 101 -> 102
second distinct event accepted
affected region = DYNAMIC only
stale execution forbidden
DYNAMIC rebuild handoff error = 0
wire/branch-b lost
load B OFF
mixed execution resumes
```

Это основной anti-single-shot falsifier первого COMPLEX2 checkpoint.

## Determinism

Determinism проверяется не повторным использованием stateful FABRIC runtime в одном SceneTree, а двумя независимыми Godot-процессами.

Оба exact runs получили:

```text
COMPLEX2_EXPERIMENT_HASH=
7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

Каждый run:

```text
FABRIC COMPLEX2 Modular Machine Acceptance: PASS (2115 assertions)
```

## Visual Modular Machine Lab

Сцена:

```text
res://scenes/labs/fabric/complex2_modular_machine_lab.tscn
```

Observer показывает:

```text
MIXED_BASELINE
LOCAL_CONTACT
DETACH_MODULE
REPRESENTATION_SWAP
SECOND_EVENT
```

25 module blocks окрашиваются по representation kind; contact stage подсвечивает active tooling; module 24 визуально отделяется; FULL/HYBRID меняют representation colours после swap; functional branches исчезают только когда их generic support relation реально потеряна.

Visual parser acceptance:

```text
FABRIC COMPLEX2 Scene Smoke: PASS (3 assertions)
```

Visual layer остаётся read-only и не участвует в canonical ownership.

## Exact identity

```text
HEAD  8d10a4e00b616c28e62cd16b4645342dc8256632
TREE  7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4
carrier run 33864290741
artifact 9933326912
artifact digest sha256:fd2901a506b285f0b7b9ff0569a30dd72afc976476f990b3690da8715c0dd028
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Project Control на exact code subject: SUCCESS.

Focused runner запускает два independent COMPLEX2 processes и scene smoke. Closed BRIDGE-2 core не меняется этой веткой; его dedicated workflows остаются отдельными regression gates.

## Что ещё нужно для COMPLEX2 CLOSED

COMPLEX2-A закрывает composition/contact/detach/swap/second-event baseline, но весь COMPLEX2 пока OPEN.

Следующие checkpoints:

1. **COMPLEX2-B — Compliant / Spring Response Envelope**;
2. **COMPLEX2-C — Articulated + Rotating Coupled Motion**;
3. **COMPLEX2-D — Independent Structural Support Failure**;
4. **COMPLEX2-E — Settle → Rebake → Re-impact Lifecycle**;
5. **COMPLEX2-PERF — 500 / 1000 / 2000 scaling matrix**;
6. **COMPLEX2-CLOSE — final exact closure review**.

`FABRIC0.19` остаётся NOT AUTHORIZED, пока один из этих executable falsifiers не докажет отсутствие необходимого generic physical primitive.
