# T1A.3 — Item Graph Materialization

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a3-item-graph-materialization`  
**Base:** T1A.2 accepted @ `47d41c097941b834c3b5eab79510a0a8c39d873d`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `ACCEPTED`

## Решение

T1A.3 принят после exact Windows focused gate и полного `RUN_WORLD_REGRESSION_TESTS.ps1` на Godot `4.7.1.stable.double.custom_build.a13da4feb`.

```text
SOURCE_ACCEPTED       = true
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = true
PRODUCTION_READY      = false
```

## Что материализовано

T1A.2 использовал `item/t1/d0/...` только как reserved semantic references. T1A.3 детерминированно переводит их в production global `item/<uuid-v4>` identities, не меняя canonical Construction identity:

```text
construct/t1/lunar-outpost/d0
part/t1/d0/p0000..p0063
```

T1A.3 повторно строит D0 через `ConstructAggregate`, сохраняя 64 parts, 112 bonds, `state_revision=177` и `OPERATIONAL`, но root/part `item_instance_id` уже являются valid production global IDs.

## Authoritative composition

До assembly transaction создаются:

```text
64 structural source Items
6 interactive fixture WORLD Items
```

Далее существующий путь:

```text
ConstructionItemTransactionPlanner
  -> AuthoritativeConstructionItemGraphAdapter
  -> ConstructionM0TransactionBridge
  -> atomic Item Graph + Operation Ledger + ConstructStore commit
```

После commit:

```text
1 construct-root Item
64 ATTACHMENT structural Items
6 WORLD interactive fixture Items
---------------------------------
71 production Items
```

Interactive fixture semantics пока сознательно deferred: `gameplay_semantics_materialized=false`.

## Focused Windows validation

Tested implementation head:

```text
db90a1c21368060500bfca0da117a059cbcab5b8
```

Результат:

```text
Editor import                         PASS
T1A.2 authoritative D0               PASS 186 assertions
C2B authoritative Item Graph         PASS 194 assertions
M0 aggregate transaction             PASS 82 assertions
T1A.3 Item Graph materialization     PASS 865 assertions
Focused gate                         PASS
```

## Full composition validation

Full regression tested metadata head:

```text
92178a00de8c6de0e98f7ef55c4540748d139cde
```

Подтверждено:

```text
RL3 representation streaming processes  PASS 37 assertions
main_scene_cli_all                       PASS 6/6
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## P0 guards

T1A.3 не добавляет:

```text
private T1 ItemRegistry
private Operation Ledger
private transaction coordinator
private Construction↔Item RPC bridge
private persistence path
authority/server routing in Item identity
LOD/visual profile in canonical identity
MaterialDefinitionId/private material ontology
```

Общий C2B/M0 foundation остаётся владельцем atomic cross-domain commit.

## Следующий checkpoint

`T1A.4 — Interactive Fixture Binding`

Цель следующего этапа — связать уже существующие 6 production Item entities D0 с реальными container/behavior/utility contracts, не создавая T1-specific foundation и не смешивая binding с renderer/network ownership.
