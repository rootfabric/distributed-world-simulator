# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** 🟡 IMPLEMENTED / exact verification pending  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**Predecessor:** `COMPLEX1B` ✅ CLOSED @ closure carrier `50574d70a9f7abd5d21e54ab09755a567656f554`.

## Цель

COMPLEX2 повышает сложность не количеством визуальных объектов, а одновременной композицией нескольких структурных, динамических, контактных и функциональных подсистем.

Первый executable envelope:

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

## BRIDGE-2 R1 boundary

Closed BRIDGE-2 R1 требует ровно пять execution regions и ровно один region каждого kind:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

COMPLEX2 не ослабляет этот контракт. Поэтому 25 logical modules размещаются поверх пяти execution partitions. Один logical module не становится новым physical authority owner.

Это важный falsifier: сложность canonical object должна расти быстрее числа representation owners.

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

Каждый module владеет ровно 80 canonical parts. 25 × 80 = 2000.

Module graph имеет chain supports и дополнительные braces. Detachable module 24 соединён с основной машиной критическим `support/complex2-23-24`.

## Functional paths

Используется generic conservation FABRIC через существующий COMPLEX1A fixture, без machine-specific solver primitives.

```text
source/battery
  ├─ wire/branch-a -> load A
  │       supported by support/complex2-23-24
  │
  └─ wire/branch-b -> load B
          supported by support/complex2-10-11
```

Ожидаемая causal sequence:

```text
baseline      A ON  B ON

detach #24
  ↓
support/23-24 lost
  ↓
wire/branch-a lost
  ↓
A OFF, B ON

second event
  ↓
support/10-11 lost
  ↓
wire/branch-b lost
  ↓
A OFF, B OFF
```

Никакого hardcode `module detached -> load off` нет: downstream state вычисляется через `Fabric.solve()` после generic `SUPPORT_TOPOLOGY_LOST`.

## Physical execution sequence

### 1. Normal movement

Mixed BRIDGE-2 runtime получает drive flow в DYNAMIC_ROM и HYBRID_BAKE regions. Каждый step сравнивается с FULL reference.

Required:

```text
max |MIXED - FULL| <= 1e-12
```

### 2. Local contact

Один contact impulse маршрутизируется только через `region/complex2-contact` external flow entry. Contact state должен заметно измениться, при этом mixed result обязан совпасть с FULL reference.

### 3. Detachable module event

Canonical module graph теряет `support/complex2-23-24`.

Required results:

```text
module 24 becomes singleton component
module revision +1
same event ID drives functional branch-A loss
only HYBRID source partition changes
HYBRID artifact becomes STALE
mixed execution blocks fail-closed
single-region rebuild has state handoff error = 0
```

### 4. Stabilization + representation swap

После rebuild машина снова проходит несколько mixed/FULL steps, затем один representation event атомарно меняет:

```text
region/complex2-full   FULL -> HYBRID_BAKE
region/complex2-hybrid HYBRID_BAKE -> FULL
```

Representation set остаётся ровно тем же, handoff error = 0, event ledger получает ровно одну запись.

### 5. Second event after reconfiguration

Уже после representation swap ломается `support/complex2-10-11`.

Required:

```text
module revision +1 again
same machine event ledger accepts second distinct event
functional branch B lost
DYNAMIC region alone invalidated
stale execution forbidden
DYNAMIC rebuild error = 0
mixed execution resumes
A OFF / B OFF
```

Это защищает COMPLEX2 от single-shot fixture, который умеет только один заранее подготовленный переход.

## Determinism

Полная последовательность запускается дважды.

Сравниваются:

```text
machine_hash
final_state_hash
experiment_hash
final functional solution
```

Все значения должны совпасть.

## Acceptance

```text
res://tests/research/fabric_bake0/fabric_bake_complex2_modular_machine_acceptance.gd
```

Runner:

```bash
bash ./RUN_FABRIC_COMPLEX2_TESTS.sh
```

Runner также обязательно повторяет закрытый BRIDGE-2 generic-machine regression.

## Что этот checkpoint ещё не закрывает

COMPLEX2 пока не CLOSED. Первый checkpoint доказывает composition, contact, detach, functional consequence, representation swap и second-event lifecycle.

Дальше внутри COMPLEX2 следует усилить:

1. реальный visual modular-machine observatory;
2. отдельный structural-support failure не совпадающий с detachable endpoint;
3. explicit compliant/spring response envelope;
4. более сильные moving-subsystem interactions;
5. rebake-after-settling scenario;
6. performance counters для 500/1000/2000 canonical parts;
7. final exact closure gate.

`FABRIC0.19` не авторизуется заранее. Если COMPLEX2 обнаружит физический falsifier, который нельзя выразить существующими FLOW/JUMP/topology/event semantics, только тогда вопрос возвращается на архитектурный review.
