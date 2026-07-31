# Дорожная карта строительной линии PlanetSimulator

## Стратегия интеграции

Строительный трек развивается отдельно до завершения базовой multiplayer-линии. Он не создаёт второй Item Graph, authority или transport path. После стабилизации M6/A3 ядро подключается к canonical multiplayer через Generic Aggregate и multi-aggregate transactions.

## C0 — архитектурная фиксация

- парадигма стройки нового уровня;
- границы Item Graph/ConstructAggregate;
- графы, facets, capabilities;
- сетевые команды;
- сценарии стола, робота, дома, сборщика и корабельной секции.

Статус: выполнено этим checkpoint.

## C1 — Semantic Construction Kernel

- строгие `PartRecord`, `BondRecord`, `ConstructSnapshot`;
- item-backed root identity;
- revision/replay fence;
- deterministic snapshot/checksum;
- capability compiler;
- стол как первый vertical slice;
- повреждение bond и разделение rigid islands.

Статус: первая реализация выполнена отдельно от gameplay runtime.

## C2 — Item Graph transaction integration

- реальное изъятие деталей из контейнеров;
- `part_of_construct` и mounted relations;
- атомарная установка/снятие;
- rollback расхода;
- Operation Ledger через существующий canonical service;
- deconstruction с возвратом предметов.

Gate: завершённая multiplayer-база и согласованный multi-aggregate command path.

## C3 — BuildPlan

- ghost construct;
- material requirements;
- этапы и инструменты;
- resumable jobs;
- repair/deconstruction plans;
- простой builder agent.

## C4 — Composite Definition

- promotion сборки в повторно используемый composite;
- exposed ports;
- параметры;
- definition/instance separation;
- versioning;
- раскрытие внутреннего состава.

## C5 — Affordance и Capability Layer

- support surface;
- container;
- seat;
- climbable;
- workstation;
- mounting surface;
- агент использует пользовательский объект без зависимости от имени prefab.

## C6 — Mobile Construct

Наземный робот: корпус, колёса, моторы, батарея, контроллер, sensor и container. Проверяются rigid islands, joints, power/control graphs и partial failures.

## C7 — Spatial Construct

Небольшой дом: фундамент, стены, дверь, две комнаты, энергия и рабочее место. Проверяются Space Graph, enclosure и section activation.

## C8 — Fabrication Cell

Сборщик исполняет BuildPlan и производит тот же table construct, что ручная сборка.

## C9 — Damage, Split, Repair

- ослабление и разрушение bonds;
- отделение частей;
- новые aggregate IDs;
- transfer momentum;
- repair ghost;
- восстановление item parts.

## C10 — Parametric Members

Балки, панели, трубы, кабели, профили и слоистые стены с вычисляемым расходом материала.

## C11 — Local Geometry Editing

Локальные CSG/SDF/voxel regions, отверстия, вырезы и обработка поверхности без потери семантических частей и портов.

## C12 — Multiplayer Acceptance

Два графических клиента, contention, reconnect, replay, permissions, checksum convergence и отсутствие двойного расхода материалов.

## C13 — Federated Large Constructs

Section aggregates, building coordinator, cross-section ports, spatial authority и compute-worker proposals.

## Acceptance C1

- оба focused Godot tests проходят;
- snapshot JSON-safe и checksum-protected;
- duplicate IDs и неизвестные endpoints отклоняются;
- exact replay не меняет revision;
- operation collision и stale revision отклоняются;
- failed operation не блокирует корректный retry с тем же operation ID;
- повреждение bond меняет build state и rigid island count;
- invalid snapshot load транзакционен;
- код не подключён к M4/M5 runtime.
