# T1A.3 — Item Graph Materialization

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a3-item-graph-materialization`  
**Base:** T1A.2 accepted @ `47d41c097941b834c3b5eab79510a0a8c39d873d`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `FOCUSED PASS — FULL REGRESSION REQUIRED`

## Цель

T1A.2 доказал canonical Construction state D0, но его `item/t1/d0/...` значения были только reserved semantic references. Production Item Graph требует global `item/<uuid-v4>` identity. T1A.3 впервые материализует реальные Item entities и связывает их с D0 через уже существующий C2B/M0 transaction foundation.

## Identity resolution

Сохраняются:

```text
construct/t1/lunar-outpost/d0
part/t1/d0/p0000..p0063
```

Меняется только Item identity boundary:

```text
reserved semantic ref
item/t1/d0/structural/p0000
        ↓ deterministic SHA-256 mapping
production global Item ID
item/xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx
```

Mapping детерминирован и возвращается отдельно как semantic↔global table. Reserved IDs не записываются в production ItemRegistry.

## Canonical ConstructSnapshot

T1A.3 повторно прогоняет D0 через `ConstructAggregate`, сохраняя те же 64 part IDs, 112 bonds, `state_revision=177` и `OPERATIONAL`, но root/part `item_instance_id` уже являются valid global Item IDs.

Это сознательная stage migration T1A.2 reserved-reference snapshot → T1A.3 production-Item-backed snapshot. Construction identity и topology не меняются.

## Item Graph source state

До assembly transaction создаются production Item entities:

```text
64 structural source Items
6 interactive fixture source Items
-------------------------------
70 source Items
```

Все имеют valid global IDs и WORLD relation.

Interactive fixture semantic refs:

```text
item/t1/d0/door/main
item/t1/d0/container/storage
item/t1/d0/generator/main
item/t1/d0/battery/main
item/t1/d0/lamp/main
item/t1/d0/console/main
```

Они материализуются как Item entities, но T1A.3 не объявляет door/container/power gameplay semantics готовыми. В component `t1_fixture` остаётся `gameplay_semantics_materialized=false`.

## Authoritative transaction

Материализация construct-root и привязка structural Items выполняется существующим путем:

```text
T1A.3 resolved ConstructSnapshot
  + 64 source part projections
  + root projection
        ↓
ConstructionItemTransactionPlanner.build_assembly_plan
        ↓
AuthoritativeConstructionItemGraphAdapter.apply_plan
        ↓
ConstructionM0TransactionBridge
        ↓
atomic Item Graph + Operation Ledger + ConstructStore commit
```

После commit:

```text
1 construct root Item
64 ATTACHMENT structural Items
6 WORLD interactive fixture Items
---------------------------------
71 production Items
```

Authority revisions ожидаются `item_graph_revision=1`, `ledger_revision=1`, `server_tick=1`; exact replay не меняет state.

## P0 guards

T1A.3 не добавляет:

```text
private T1 ItemRegistry
private Operation Ledger
private transaction coordinator
private Construction↔Item RPC bridge
authority/server routing in Item ID
LOD/visual profile in canonical identity
MaterialDefinitionId/private material ontology
```

Общий C2B/M0 foundation остаётся владельцем atomic cross-domain commit.

## Focused validation — PASS

Exact Windows engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
candidate head: db90a1c21368060500bfca0da117a059cbcab5b8
```

Результат:

```text
Editor import                         PASS
T1A.2 authoritative D0 dependency    PASS 186 assertions
C2B authoritative Item Graph         PASS 194 assertions
M0 aggregate transaction             PASS 82 assertions
T1A.3 Item Graph materialization     PASS 865 assertions
Focused gate                         PASS
```

Таким образом deterministic global Item mapping, preserved construct/part identity, 71 production Items, 64 ATTACHMENT bindings, 6 deferred interactive WORLD Items, valid Item Graph, authoritative revision chain и exact replay подтверждены на целевой Windows сборке Godot.

## Status dimensions

```text
SOURCE_ACCEPTED       = false
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = false
PRODUCTION_READY      = false
```

`SOURCE_ACCEPTED` и `COMPOSITION_VERIFIED` остаются false только до полного `RUN_WORLD_REGRESSION_TESTS.ps1` на T1A.3 branch.

## Следующий checkpoint

После full regression acceptance:

`T1A.4 — Interactive Fixture Binding`

Он сможет отдельно материализовать реальные container/door/power/data capabilities, не перегружая T1A.3 дополнительной gameplay семантикой.
