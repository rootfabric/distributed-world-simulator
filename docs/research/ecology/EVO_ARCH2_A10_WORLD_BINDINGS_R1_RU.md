# EVO ARCH2 A10 — selective world bindings R1

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R1`, HIGH.
База: `main@471210d781e521bc7897a8fe859636a07d7a3ab3`, TREE `5a4576f365c60fe117e03b9aee31b2359249b7a5`.

## Цель

Начать A10 как **selective integration from current main**. ECO не получает собственных production-владельцев Terrain, Matter, Construction, Authority, Region, Network или Persistence. R1 добавляет только адаптер/admission layer и его exact tests.

Первый вертикальный срез должен доказать три вещи на реальных current-main contracts:

1. production Matter/terrain sample можно привязать к ECO site без подмены физической семантики;
2. A8 ecological cursor допускается к исполнению только когда он совпадает с canonical production Region owner/epoch;
3. применённый C9 Construction damage можно детерминированно перевести в ECO body-module damage event только через явное part→module binding.

## Production sources — read only

R1 использует неизменённые владельцы:

- `scripts/simulation/matter/query/matter_query_result.gd`;
- `scripts/simulation/matter/contracts/matter_sample.gd`;
- `scripts/network/contracts/authority_region_descriptor.gd`;
- `scripts/network/contracts/handoff_ticket.gd`;
- `scripts/construction/damage/construction_damage_request.gd`;
- `scripts/construction/damage/construction_damage_record.gd`;
- `scripts/construction/contracts/construct_snapshot.gd`;
- `scripts/construction/contracts/construction_part_record.gd`;
- `scripts/research/ecology/v2/body_graph_v1.gd`;
- A8/A9 ECO contracts из `scripts/research/ecology/v2/**`.

Ни один из этих файлов R1 не изменяет.

## Matter / terrain binding

A10 R1 не выводит `water_mg/nutrient_mg/organic_mg` из одной point-sample. `MatterQueryResult` даёт физический sample — density, composition, integrity, temperature, porosity — но не доказанный ecological reservoir volume.

Поэтому R1 сохраняет физические значения и provenance byte-for-semantics и публикует только:

- canonical body/frame/cell/brick identity;
- R1 допускает только production Region selector `GLOBAL_SPACE`; `CHUNK_SET/PARTITION_PREFIX` fail-closed, потому что current-main contracts не дают канонического cell→chunk/partition membership witness;
- Matter state revision;
- material mass fractions;
- density/occupancy/integrity/temperature/porosity;
- признак `resource_stock_authority = NOT_DERIVED_FROM_POINT_SAMPLE`.

Любая будущая выдача mass/resource потребует отдельного volumetric transaction contract, а не умножения point density на придуманную площадь.

## Production authority admission

A10 не создаёт `EcoRegion`. A8 cursor должен совпасть с production `AuthorityRegionDescriptor`:

- `region_id`;
- `owner_node_id`;
- `authority_epoch`;
- lifecycle только `WARM|ACTIVE`.

Несовпадение region/owner/epoch или DORMANT/UNLOADING fail-closed. Нельзя выводить принадлежность Matter cell к `CHUNK_SET/PARTITION_PREFIX` из похожих строк; partition-specific binding требует отдельного production membership witness.

## Construction damage binding

A10 не исполняет C9 damage и не редактирует Construction. Он принимает только пару:

`ConstructionDamageRequest + APPLIED ConstructionDamageRecord`

с совпадающими `damage_id` и `request_checksum`. Сам `DamageRecord` допускается только при совпадении с caller-owned external trusted `record_checksum`; self-contained checksum внутри переданного JSON не считается authority proof. Дополнительно передаётся exact source `ConstructSnapshot`: его checksum обязан совпасть с `source_snapshot_checksum` запроса, а каждый затронутый part должен реально существовать в этом snapshot.

Влияние на ECO разрешено только для part IDs, явно перечисленных в immutable `part_to_module` binding. Каждый target module обязан реально существовать в валидном ECO `BodyGraph`; event запечатывает `body_hash`. `DEGRADED` и `DESTROYED` переводятся в канонические ECO damage events; неизвестный part, лишний module, конфликтующий map или REPAIRED record не допускаются как новое биологическое повреждение.

## Не входит в R1

- изменение production Matter;
- расход/депозит Matter от роста;
- физическая проекция всего BodyGraph в Construction;
- применение damage event к A7 state;
- coarse population dynamics;
- A11 playable habitat;
- изменение registry/scheduler/production ownership;
- main merge или acceptance.

## Acceptance R1

- additive diff относительно exact current main;
- production contract files byte-identical current main;
- Godot test строит валидный current-main MatterQueryResult и RegionDescriptor, затем проверяет admission/negative cases;
- Godot test связывает валидный C9 damage request/record только при внешнем exact record-checksum anchor с exact source ConstructSnapshot и существующими BodyGraph modules, отвергая stale/forged/repaired/unknown-source/unknown-module paths;
- никакая функция R1 не возвращает ecological resource stock, полученный из point Matter sample;
- Python verifier fail-closed проверяет exact HEAD/TREE/base ancestry и scope;
- fresh review + independent verifier требуются до R1 acceptance.

После R1 следующий bounded slice A10-R2 может добавить volumetric Matter exchange и применение damage к organism state, только если source contracts дают сохранение массы и replay/authority guarantees.

## Base refresh 2026-09-18

Во время публикации R1 canonical main продвинулся с `99e8efe2` до `471210d7` только за счёт merged Harness PR #652. Diff затрагивает harness/docs и не меняет ни один A10 production source. R1 синхронизирован merge-коммитом с current main; scope A10 остаётся additive.
