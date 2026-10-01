# FABRIC R5.2 / T14 — Observation-Driven Selective Refinement

Статус: **IMPLEMENTED / EXACT GATE PENDING**.

База: закрытый T13.5 merge `bb191ec4f610f1f879e48fa104ca3155464bbdc2`.

## Цель

T14 вводит per-instance observation refinement поверх T13.5 shared families.

Главный контракт:

```text
100 compact instances
        │
        │ observe one instance / one subtree
        ▼
1 instance has one detailed compiled subtree
99 instances remain compact
all non-selected siblings in observed instance remain compact
physics remains byte-equivalent
global recompile = 0
source-leaf traversal = 0
```

T14 намеренно **не является UNBAKE**. Он не восстанавливает исходные Matter/
Construction leaves и не меняет storage laws. Это следующий слой представления:
наблюдатель получает подробный hierarchical compiled view выбранного subtree,
пока физическое выполнение продолжает использовать уже проверенный compact runtime.

T15 будет использовать этот фундамент для structural divergence / selective
UNBAKE / repair / ReBAKE.

## Scenario

Используются четыре T13.5 family и 100 instances:

```text
family-a 40
family-b 30
family-c 20
family-d 10
```

Выбран:

```text
instance =
t14-instance-058

family =
family-b

path =
root/bank/unit03/cannon
```

Family B содержит GLYCOL cooling variant, поэтому выбранный cannon subtree
имеет собственную family identity и отличается от family A.

## Selective detail

До observation все 100 instances COMPACT.

После request:

```text
refined instances = 1
compact instances = 99
active refinements = 1
```

Выбранный cannon materializes только:

```text
root/bank/unit03/cannon
root/bank/unit03/cannon/cooling
root/bank/unit03/cannon/emitter
root/bank/unit03/cannon/power
```

То есть:

```text
detail nodes = 4
detail compiled leaves = 3
```

У того же instance остаются COMPACT:

```text
root/battery
root/bank/unit01
root/bank/unit02
root/bank/unit03/servo
root/bank/unit03/drive
```

Предок `root/bank/unit03` имеет resolution `MIXED`, потому что внутри него
только cannon detailed, а servo/drive compact.

## Identity / ownership

Refinement metadata привязана к:

- observation_id;
- instance binding checksum;
- family id;
- canonical owner family;
- selected path;
- exact binary subtree SHA-256;
- full compiled model checksum/hash;
- instance state revision;
- damage revision;
- deterministic detail manifest hash.

Returned detail caller-owned. Его mutation не может изменить сохранённый overlay.

Одновременно допускается только один refinement на один instance.

## No physics side effects

Acceptance сначала выполняет 100 compact control steps, затем materializes один
refinement и повторяет те же 100 steps.

Требуется:

```text
physics_equivalent_after_refinement = 100
caller instance state mutated = false
family model identity changed = false
recompile events = 0
instance compile events = 0
physics source leaf traversals = 0
```

Observation overlay не участвует в physical solver. Он является representation
layer поверх frozen compiled family.

## Snapshot / restore

Активный refinement можно snapshot'нуть в deterministic JSON envelope.

Snapshot содержит metadata/anchors, но не сериализует полный subtree.
При restore T14 повторно materializes detail из frozen family model и проверяет:

- snapshot SHA-256;
- binding/instance identity;
- family/owner identity;
- state/damage revision;
- selected subtree binary hash;
- detail node/leaf counts;
- detail manifest hash.

Cross-instance restore и byte tamper должны fail closed.

Acceptance выполняет:

```text
request
snapshot
release
cross-instance restore reject
tampered restore reject
restore original
release
```

Финально:

```text
active refinements = 0
100 instances compact
```

## Work accounting

Один request и один restore materialize один и тот же 4-node compiled subtree:

```text
successful requests = 1
restore count = 1
release count = 2
materialization count = 2
compiled nodes visited = 8
source leaf traversals = 0
recompile events = 0
family prepares = 4
T13.5 compile events remain = 42
```

## Что T14 не заявляет

T14 не:

- UNBAKE'ит source graph;
- создаёт structural fork;
- меняет physical state layout;
- меняет shared family model;
- recompiles affected ancestors;
- pointer-shares detailed runtime objects;
- является production visibility/LOD scheduler.

Он доказывает более узкий bridge:

```text
compact family instance
       ↓ observation
per-instance detailed compiled subtree
       ↓ release
compact family instance
```

при полной physical parity.

## Roadmap bridge

```text
T13   identical instances
  ↓
T13.5 structural families + subtree reuse
  ↓
T14   observation-driven selective refinement
  ↓
T15   local structural divergence / selective UNBAKE / ReBAKE
  ↓
T16   NO_SAFE_BAKE
  ↓
R5.3 hierarchical BAKE / recursive ROM
```
