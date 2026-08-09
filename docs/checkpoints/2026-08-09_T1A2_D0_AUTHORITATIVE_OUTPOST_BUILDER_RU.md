# T1A.2 — D0 Authoritative Outpost Builder

**Дата:** 2026-08-09  
**Ветка:** `feature/t1a2-d0-authoritative-outpost-builder`  
**Base:** `fix/t1-m5-convergence-finish-barrier @ b34a4377fd68c47522c714995d9448ae8e2e8fb9`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `IMPLEMENTED CANDIDATE`

## Цель

T1A.0 создал только детерминированный data-only fixture D0. T1A.1 доказал, что visual representation можно менять независимо от canonical identity. T1A.2 впервые материализует D0 как реальное canonical Construction state через уже существующий production Construction kernel.

```text
T1A.0 D0 fixture
    ↓
T1D0AuthoritativeOutpostBuilder
    ↓
ConstructAggregate
    ↓ add_part / add_bond / set_build_state
ConstructSnapshot v1
    ↓ standard CREATE mutation
ConstructionConstructStore
```

Новый authority foundation не вводится.

## Почему выбран именно этот путь

В проекте уже существуют необходимые владельцы semantics:

```text
ConstructAggregate
  -> revision fence
  -> operation replay fence
  -> part/bond validation
  -> capability compilation

ConstructSnapshot
  -> canonical construction DTO
  -> deterministic checksum

ConstructionConstructStore
  -> canonical construct storage
  -> CREATE / UPDATE / DELETE preconditions
```

Поэтому T1A.2 является adapter/composition stage, а не новым Construction engine.

## D0 canonical materialization

Исходный fixture сохраняется byte/semantic invariant:

```text
profile:           D0
construct_id:      construct/t1/lunar-outpost/d0
fixture checksum:  9e20be039011f6b94582dc4c7cffd2098fea0d145f3c08a3b053902764514d58
parts:             64
rooms:             1 fixture reference
utilities:         power + data fixture references
items:             6 deferred Item Graph fixture references
```

Canonical Construction graph v0 для этого этапа:

```text
8 x 8 structural grid
64 parts
112 orthogonal structural bonds
4 corner support parts
60 surface parts
single connected rigid island
OPERATIONAL build state
```

Все 64 исходных `part/t1/d0/pXXXX` identity сохраняются без перенумерации.

Для обязательного `ConstructionPartRecord.item_instance_id` используются детерминированные reserved references:

```text
item/t1/d0/structural/p0000
...
item/t1/d0/structural/p0063
```

А root construct использует:

```text
item/t1/d0/construct-root
```

Это только canonical references, требуемые существующим Construction contract. T1A.2 **не создаёт соответствующие Item Graph nodes**. Их actual Item Graph materialization остаётся T1A.3.

## Revision model

Builder не конструирует snapshot напрямую. Он прогоняет операции через `ConstructAggregate`:

```text
64  add_part
112 add_bond
1   set_build_state(OPERATIONAL)
---
177 canonical state revisions
```

Таким образом acceptance проверяет production revision/replay fences, а не обходит их созданием готового словаря.

## Authoritative store boundary

После получения валидного `ConstructSnapshot` builder может materialize его в существующий `ConstructionConstructStore` стандартной `CREATE` mutation.

```text
before_snapshot = {}
after_snapshot  = D0 ConstructSnapshot
operation_kind  = CREATE
```

Повторная materialization того же `construct_id` отвергается. Item Graph transaction при этом не выполняется.

## P0 invariants

T1A.2 намеренно не добавляет:

```text
Construction global address
Construction-specific authority registry
server ID в construct/part identity
LOD/HLOD в canonical identity
PartVisualProfile в ConstructSnapshot
MaterialDefinitionId или private material ontology
новый persistence format
network transport dependency
Item + Construction cross-domain commit chain
```

Границы остаются:

```text
identity != LOD/HLOD
canonical ConstructSnapshot != representation
construct local identity != authority route
reserved item reference != Item Graph materialization
Construction mutation != cross-domain transaction
```

Room/power/data IDs из D0 пока возвращаются как source fixture references для следующей композиции. T1A.2 не создаёт новый spatial/utility ontology поверх уже существующих C7/C15 contracts.

## Focused validation

Windows exact-engine gate:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_T1A2_D0_AUTHORITATIVE_OUTPOST_BUILDER_TESTS.ps1 `
    -GodotPath $Godot
```

Runner выполняет:

```text
editor import
T1A.0 fixture dependency
T1A.1 presentation-boundary dependency
C1 ConstructAggregate dependency
C2B authoritative construct-store dependency
T1A.2 D0 authoritative builder acceptance
```

T1A.2 acceptance требует:

```text
fixture unchanged
fixture part identities preserved
64 canonical parts
112 canonical structural bonds
state_revision = 177
build_state = OPERATIONAL
connected = true
stable = true
rigid_island_count = 1
deterministic repeated snapshot/checksum
ConstructionConstructStore CREATE roundtrip
second CREATE rejected
no visual/LOD/authority-route/material-definition fields in snapshot
six D0 gameplay Item Graph IDs remain deferred
```

После focused PASS требуется обычный:

```powershell
$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Новый focused acceptance script специально не называется `test_*.gd`, поэтому до SOURCE_ACCEPTED он не расширяет автоматический global regression discovery manifest. После focused + full regression acceptance его можно включить в постоянный global runner отдельным integration commit.

## Текущий статус

```text
SOURCE_ACCEPTED       = false
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = false
PRODUCTION_READY      = false
```

Причина: код опубликован как candidate, но exact Windows focused gate для текущего implementation head ещё не получен.

## Следующий checkpoint после acceptance

```text
T1A.3 — Item Graph Materialization
```

T1A.3 должен создать реальные Item Graph entities для root/structural/interactive item references и связать их с уже существующим authoritative D0 ConstructSnapshot. Если понадобится операция, атомарно меняющая Item + Construction canonical truth, stage обязан использовать общий transaction foundation, а не private T1 RPC chain.
