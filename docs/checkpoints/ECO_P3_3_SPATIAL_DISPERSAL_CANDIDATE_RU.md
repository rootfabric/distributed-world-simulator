# ECO / P3.3 — Spatial Dispersal — CANDIDATE

Статус: `CANDIDATE / RESEARCH_ONLY / TARGETED LINUX PASS / EXACT WINDOWS CANONICAL PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Accepted parent:

```text
ECO.P3.2 Density & Carrying Capacity
aggregate = 172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
status = ACCEPTED_EXACT_WINDOWS_CANONICAL
```

## Цель

P3.3 добавляет явное spatial neighbourhood состояние поверх локальных P3.2 результатов.

P3.2 остаётся локальным patch kernel и не меняется. P3.3 принимает несколько валидных P3.2 `density_result` и переносит часть их `next_biomass_kg` по directed patch/cell graph.

Это не повтор старого EVO1/P2.1 seed-event kernel. P2.1 исследовал individual seed release/dispersal events и геометрические расстояния. P3.3 решает другой уровень: deterministic transfer уже агрегированной локальной biomass между явными patch/cell neighbours после P3.2 local update.

## Input contract

Каждый patch:

```text
id: non-empty unique String
density_result: valid P3.2 result
boundary_export_fraction: finite [0,1]
```

Global config:

```text
dispersal_fraction: finite [0,1]
```

Directed edge:

```text
from: known patch ID
to: known patch ID, != from
weight: finite > 0
```

Duplicate directed edges fail closed.

Outgoing weights нормализуются в canonical shares. Поэтому `3:1` и `30:10` для одной source patch имеют одну и ту же semantic topology и один result hash.

## Transfer semantics

Для каждого source plant:

```text
source = P3.2 next_biomass_kg
dispersal_pool = source * dispersal_fraction
boundary_export = dispersal_pool * patch.boundary_export_fraction
internal_pool = dispersal_pool - boundary_export
```

Если есть internal outgoing neighbours:

```text
retained = source - dispersal_pool
transfer(to) = internal_pool * normalized_edge_share(to)
```

Если internal neighbour отсутствует:

```text
retained = source - boundary_export
```

То есть невозможная внутренняя миграция не уничтожает biomass. Только явный boundary sink может вывести её за пределы моделируемой системы.

Incoming biomass может создать plant record на destination patch, где такого ID не было в source P3.2 state. Это colonization через conserved transfer, а не создание biomass из ничего.

## Conservation

P3.3 требует:

```text
total_source_biomass
= total_final_in_patch_biomass + total_boundary_export
```

и отдельно:

```text
total_internal_transfer
= total_incoming_biomass
```

с tolerance `1e-12`.

Closed graph с `boundary_export_fraction = 0` сохраняет total biomass полностью.

## Determinism / canonicalization

Canonical order:

```text
patch IDs: lexical
edges: from -> to lexical
patch plant IDs: lexical
transfers: from -> to -> plant ID lexical
boundary records: patch -> plant ID lexical
```

Input patch/edge permutation не меняет result hash.

Kernel не вызывает RNG. Отдельный seeded global-RNG probe доказывает, что sequence до/после P3.3 не сдвигается.

## Fail-closed coverage

Проверены:

- negative / >1 dispersal fraction;
- unexpected config fields;
- duplicate patch IDs;
- invalid boundary fraction;
- self edge;
- missing destination;
- duplicate directed edge;
- zero edge weight;
- overflow/non-finite outgoing weight sum;
- unexpected patch/edge field;
- tampered P3.2 parent;
- tampered transfer;
- tampered patch totals;
- tampered canonical plant order;
- tampered P3.2 parent aggregate pin.

Validator reconstructs expected result from canonical source P3.2 snapshots, normalized topology and config, then requires exact deterministic result hash equality.

## Targeted Linux evidence

Attached Godot binary:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Parser/preload:

```text
PASS
```

Accepted P3.2 targeted parent regression immediately before P3.3 publication:

```text
ECO.P3.2 Density & Carrying Capacity: PASS (79 assertions)
aggregate_hash=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

Fresh processes A/B/C were identical:

```text
ECO.P3.3 Spatial Dispersal: PASS (66 assertions)
aggregate_hash=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
network_hash=21a8de4b12cd541d40c8fd34b725e59e493a775e3465b853945f46f85445a8a2
closed_hash=039fb7fc353e36f4d0d42fa146760062704e91a6ed21c03bff8213feec96cc5f
isolated_hash=14d1d467d65047e362fc6bd04dd668ab1713d986c1bb97f79734ecc0370441ec
parent_p3_2=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

## Canonical gate

`RUN_ECO_P3_3_TESTS.ps1`:

1. requires factual P3.2 validation status `ACCEPTED*`;
2. parser/preload P3.3;
3. runs full `RUN_ECO_P3_2_TESTS.ps1` accepted parent regression;
4. runs P3.3 process A;
5. runs fresh process B;
6. requires equal P3.3 aggregate hashes;
7. requires exact accepted P3.2 parent aggregate.

Targeted Linux PASS does not equal canonical acceptance.

```text
P3.3 = CANDIDATE
P3.3 != ACCEPTED
P3.4 = NOT OPENED
```
