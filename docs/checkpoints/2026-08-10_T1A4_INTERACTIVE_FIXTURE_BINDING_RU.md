# T1A.4 — Interactive Fixture Binding

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a4-interactive-fixture-binding`  
**Base:** T1A.3 accepted @ `5e051f67bf6987a354de5b565da1448be6b0b4db`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `ACCEPTED`

## Acceptance status

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Exact Windows focused gate прошёл на Godot `4.7.1.stable.double.custom_build.a13da4feb`:

```text
T1A.3 Item Graph materialization      PASS 865
C5 capability/affordance contracts   PASS 105
C15 executable utilities contracts   PASS 92
C2B authoritative Item Graph         PASS 194
T1A.4 direct acceptance              PASS 153
T1A.4 focused runner                 PASS
Focused total                        1409 assertions PASS
```

Focused tested head: `f5a2f3349ebb7be663f72a0bd435ae9386ce46a1`.

Full `RUN_WORLD_REGRESSION_TESTS.ps1` затем прошёл на metadata head `a81b56fdce2cc0b09d022989d866988faf92026f` до финального sentinel:

```text
main_scene_cli_all  6 PASS / 0 FAIL
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Report path: `C:\Godot\lunar-world-t1-construct\artifacts\test-results\world-regression-summary.json`.

Acceptance closeout metadata head: `784eebfacdebf98b2e6a681f8ea70ca3b9626559`.

Предыдущий parse blocker был test-only и закрыт fix1 `eee48dee636b3fee4d2504049df3a069910f5ca6` явной типизацией M0 report как `Dictionary`.

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

Первый deterministic simulation tick обслуживает door/lamp/console demands полностью в focused acceptance.

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

`ConstructSnapshot` остаётся semantic equivalent T1A.3 snapshot; binding data живут в Item Graph/C5/C15 artifacts.

## Следующий checkpoint

`T1A.5 — Interactive Runtime Execution`

T1A.5 должен реализовать исполняемое authoritative состояние `OPEN/CLOSE`, generator start/stop, light toggle и console interaction, используя закреплённые T1A.4 capability/utility bindings и существующую operation/replay foundation. Runtime state не должен становиться частью `ConstructSnapshot`, permanent Item identity, LOD или authority-routing identity.
