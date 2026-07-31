# Дорожная карта строительной линии PlanetSimulator

## Стратегическая цель

PlanetSimulator создаёт **конструктор нового уровня** на основе сочетания:

- семантического масштаба;
- составных предметов;
- компиляции facets;
- capability-based поведения.

Наглядная актуальная карта: `docs/plans/CONSTRUCTION_MAP_RU.md`.
Хронология решений: `docs/plans/CONSTRUCTION_PROGRESS_LOG_RU.md`.

## Стратегия интеграции

Строительный трек развивается отдельно до завершения базовой multiplayer-линии. Он не создаёт второй Item Graph, authority, persistence или transport path. Реальная интеграция выполняется только через canonical Generic Aggregate, Item Graph services, Operation Ledger и M0 multi-aggregate transactions.

## C0 — архитектурная фиксация

- парадигма стройки нового уровня;
- границы Item Graph/ConstructAggregate;
- графы, facets, capabilities;
- сетевые команды;
- сценарии стола, робота, дома, сборщика и корабельной секции.

**Статус:** ACCEPTED.

## C1 — Semantic Construction Kernel

- строгие `PartRecord`, `BondRecord`, `ConstructSnapshot`;
- item-backed root identity;
- revision/replay fence;
- deterministic snapshot/checksum;
- capability compiler;
- стол как первый vertical slice;
- повреждение bond и разделение rigid islands.

**Статус:** ACCEPTED, fix1.

## C2A — Item Graph Contracts

Изолированный контрактный этап без подключения к runtime.

- совместимая проекция `item_instance.v2`;
- создание construct root item;
- `ATTACHMENT` как связь item-backed part с construct;
- item mutations `CREATE/UPDATE/DELETE`;
- construct mutations `CREATE/UPDATE/DELETE`;
- checksum-protected transaction plan;
- exact before-state preconditions;
- root/identity/part-binding invariants;
- атомарный in-memory adapter;
- exact replay и operation-ID conflict;
- retryable failure и rollback;
- JSON persistence контракта;
- сборка и разборка стола;
- расход материалов без автоматического salvage.

**Статус:** IMPLEMENTED CANDIDATE.

### Acceptance C2A

- оба C2A focused tests проходят;
- C1 focused tests не деградируют;
- оба C2A tests внесены в обязательный world regression;
- plan JSON-safe, canonical, checksum-protected;
- exact replay не меняет generation;
- conflicting payload с тем же operation ID отклоняется;
- stale before-state отклоняется;
- retryable failure ничего не фиксирует и не блокирует повтор;
- сборка создаёт root item, construct и пять согласованных attachment bindings;
- разборка удаляет root/construct и возвращает детали;
- consumed fasteners не восстанавливаются;
- полный network/world regression проходит на основном checkout.

## C2B — Authoritative Item Graph Integration

Реальная интеграция после multiplayer gate.

- реальное изъятие деталей из контейнеров;
- mapping C2A transaction plan → M0 MutationBatch;
- canonical `AggregatePrecondition` для item, container и construct;
- атомарная установка/снятие;
- общий Operation Ledger;
- persistence/recovery boundary;
- reconnect/replay без повторного расхода;
- deconstruction с slot allocation и container capacity validation.

**Gate:** завершённая multiplayer-база и согласованный multi-aggregate command path.
**Статус:** BLOCKED BY GATE.

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
