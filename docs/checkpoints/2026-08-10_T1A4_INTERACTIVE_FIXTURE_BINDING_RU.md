# T1A.4 — Interactive Fixture Binding

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a4-interactive-fixture-binding`  
**Base:** T1A.3 accepted @ `5e051f67bf6987a354de5b565da1448be6b0b4db`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `IMPLEMENTED CANDIDATE`

## Цель

T1A.3 создал 71 production Item entity, включая шесть интерактивных WORLD fixtures, но оставил `gameplay_semantics_materialized=false`. T1A.4 связывает эти шесть Item identities с существующими production contracts, не меняя canonical `ConstructSnapshot` и не создавая T1-specific foundation.

## Binding model

```text
D0 Item Graph from T1A.3
  ├─ door
  ├─ storage container
  ├─ generator
  ├─ battery
  ├─ lamp
  └─ console
        │
        ├─ C5 capability / affordance descriptors
        ├─ production ContainerRegistry (storage)
        └─ C15 POWER / DATA utility contracts
```

Canonical Construction identity сохраняется:

```text
construct/t1/lunar-outpost/d0
64 part identities
112 bonds
state_revision = 177
```

Binding/runtime artifacts не записываются в `ConstructSnapshot`.

## Host part binding

Интерактивные Items остаются самостоятельными WORLD entities и получают semantic host-part references:

```text
DOOR       -> part/t1/d0/p0025
CONTAINER  -> part/t1/d0/p0026
GENERATOR  -> part/t1/d0/p0027
BATTERY    -> part/t1/d0/p0028
LAMP       -> part/t1/d0/p0029
CONSOLE    -> part/t1/d0/p0030
```

Это binding, а не перенос Item identity внутрь Part identity.

## Behavior contracts

T1A.4 использует существующие C5 generic descriptors.

Capabilities:

```text
DOOR_CONTROL
CONTAINER
POWER_SOURCE
POWER_STORAGE
LIGHTING
WORKSTATION
```

Affordances:

```text
OPEN_DOOR
CLOSE_DOOR
OPEN_CONTAINER
STORE_ITEM
TAKE_ITEM
START_GENERATOR
STOP_GENERATOR
INSPECT_BATTERY
TOGGLE_LIGHT
USE_WORKSTATION
```

C5 принимает generic uppercase vocabulary, поэтому новый отдельный T1 behavior framework не создаётся.

Важно: T1A.4 материализует **binding semantics**, но не объявляет готовыми renderer/UI/state-machine исполнения двери, света или консоли. Это следующий runtime checkpoint.

## Storage

Storage fixture получает настоящий item-owned production container:

```text
container_id: container/t1/d0/storage-main
owner_kind:   ITEM_INSTANCE
owner_id:     <global storage Item ID>
storage:      SLOTS
slot_count:   24
```

Item содержит обязательную `container.container_id` back-reference, поэтому существующий `ItemRelationshipValidator` проверяет ownership и graph consistency.

## POWER network

Используется C15 utility foundation:

```text
generator SOURCE
battery   STORAGE
bus       JUNCTION
door      CONSUMER
lamp      CONSUMER
console   CONSUMER
```

Utility node properties сохраняют ссылку на соответствующий global fixture Item ID, а network source pin содержит D0 `construct_id`, `state_revision=177` и checksum T1A.3 snapshot.

Первый deterministic simulation tick должен обслужить door/lamp/console demands полностью.

## DATA network

```text
console SOURCE
door    CONSUMER
storage CONSUMER
```

Door access-control и storage telemetry используют тот же C15 DATA contract. Нового T1 data bus нет.

## Authoritative bootstrap

Binding components и item-owned storage container формируются **до** C2B/M0 bootstrap. После этого существующий assembly transaction создаёт construct-root и 64 structural ATTACHMENT links.

```text
bound Item source state
  -> AuthoritativeConstructionItemGraphAdapter.setup
  -> ConstructionM0TransactionBridge.bootstrap
  -> existing ConstructionItemTransactionPlan
  -> atomic Item Graph + Ledger + Construct commit
```

Так M0 с первого committed generation видит согласованную Item/Container state; приватный item-only transaction path не добавляется.

## P0 guards

T1A.4 не добавляет:

```text
new ItemRegistry / ContainerRegistry
new behavior foundation
new utility foundation
new transaction coordinator
private Construction↔Item RPC
authority/server routing in identity
LOD/visual identity in canonical state
MaterialDefinitionId/private material ontology
```

`ConstructSnapshot` обязан остаться byte/semantic equivalent T1A.3 snapshot; binding data живут в Item Graph/C5/C15 artifacts.

## Focused gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_T1A4_INTERACTIVE_FIXTURE_BINDING_TESTS.ps1 `
    -GodotPath $Godot
```

Gate включает:

```text
editor import
T1A.3 acceptance
C5 capability / affordance contracts
C15 executable utility contracts
C2B authoritative Item Graph integration
T1A.4 acceptance
```

T1A.4 acceptance проверяет 71 Items, six bindings, item-owned 24-slot storage, behavior descriptors, POWER/DATA networks and execution profiles, M0/C2B authority revisions, exact replay и отсутствие binding/runtime полей в canonical Construction snapshot.

## Следующий checkpoint

После focused + full regression acceptance:

`T1A.5 — Interactive Runtime Execution`

Там можно отдельно реализовать исполняемое состояние `OPEN/CLOSE`, generator start/stop, light toggle и console interaction, используя уже закреплённые T1A.4 capability/utility bindings.
