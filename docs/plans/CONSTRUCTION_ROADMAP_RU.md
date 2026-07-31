# Дорожная карта строительной линии PlanetSimulator

## Стратегическая цель

PlanetSimulator создаёт **конструктор нового уровня**, основанный на сочетании:

- семантического масштаба;
- составных item-backed предметов;
- компиляции независимых facets;
- capability-based поведения;
- авторитетных сетевых транзакций;
- локальной активации сложности.

Это не вспомогательная система размещения блоков. Строительная модель должна стать общей парадигмой объектов мира: от стола и робота до дома, корабля и города.

Наглядная актуальная карта: `docs/plans/CONSTRUCTION_MAP_RU.md`.
Хронология решений: `docs/plans/CONSTRUCTION_PROGRESS_LOG_RU.md`.

## Стратегия интеграции

Строительный трек развивается последовательно поверх принятых доменных границ:

```text
C1 semantic construct
→ C2A transaction contracts
→ C2B production Item Graph + M0 authority
→ C3 resumable BuildPlan
→ C4 reusable CompositeDefinition
```

Ни один последующий этап не получает права обходить C2B. Любая реальная установка детали или расход материала выполняются через его authoritative transaction path.

## C0 — архитектурная фиксация

- парадигма стройки нового уровня;
- границы Item Graph/ConstructAggregate;
- отдельные structural, kinematic, flow, space и capability graphs;
- facets и activity levels;
- сценарии стола, робота, дома, сборщика и корабельной секции.

**Статус:** ACCEPTED.

## C1 — Semantic Construction Kernel

- строгие `PartRecord`, `BondRecord`, `ConstructSnapshot`;
- item-backed root identity;
- revision/replay fence;
- deterministic snapshot/checksum;
- capability compiler;
- стол как первый vertical slice.

**Статус:** ACCEPTED, fix1.

## C2A — Item Graph Contracts

- совместимая проекция `item_instance.v2`;
- canonical `ATTACHMENT` для установленной детали;
- item/construct mutations;
- checksum-protected transaction plan;
- exact before-state preconditions;
- атомарный in-memory adapter;
- exact replay, conflict, retryable failure и rollback;
- сборка и разборка стола.

**Статус:** ACCEPTED, commit `68cf8b2`.

## C2B — Authoritative Item Graph Integration

- реальные `ItemRegistry`, `ContainerRegistry`, relationship validator и mass service;
- общий `ItemOperationLedger`;
- deterministic C2A plan → M0 `MutationBatch`;
- M0 prepare/commit как authority;
- crash recovery из M0;
- atomic local materialization и rollback;
- persistence без права откатить M0;
- независимые internal construct revision и M0 aggregate revision.

**Статус:** ACCEPTED после полного локального regression; commit ещё должен быть создан в ветке C2B.

## C3 — BuildPlan and Ghost Construction

### Цель

Перевести стройку из мгновенной операции в resumable процесс:

```text
проект
→ невесомый ghost
→ проверка деталей, материалов и инструментов
→ стадия
→ частичный construct
→ следующая стадия
→ commissioning
→ operational construct
```

### Реализованный scope C3

#### Immutable BuildPlan

`ConstructionBuildPlan` содержит:

- build plan ID;
- construct/root identity;
- ghost world relation;
- полный target `ConstructSnapshot`;
- точные исходные item projections;
- упорядоченные stages;
- exact material allocations;
- required capabilities;
- checksum.

C3 BuildPlan является execution-plan конкретной стройки. Переиспользуемая definition/blueprint separation появляется в C4.

#### BuildStage

Каждая стадия содержит:

- sequence index;
- semantic state;
- cumulative included parts;
- cumulative included bonds;
- material allocations;
- required tool/actor capabilities.

Стадии монотонны: уже включённые parts/bonds не исчезают. Финальная стадия обязана включить полный target и перейти в `OPERATIONAL`.

#### GhostState

До первой стадии ghost:

- не входит в Item Graph;
- не имеет массы;
- не имеет capabilities;
- не создаёт collision или physics object;
- не создаёт root item;
- является intention/progress projection.

После начала стройки ghost не заменяет частичный construct, а показывает оставшийся план.

#### StageSnapshot compiler

Из cumulative stage content компилируется deterministic `ConstructSnapshot`:

- внутренний revision равен stage index;
- промежуточные состояния используют `PARTIAL`;
- final stage использует `OPERATIONAL`;
- partial capabilities принудительно пусты;
- final capabilities вычисляются тем же C1 compiler.

#### Stage transaction planner

Каждая стадия переводится в обычный C2A transaction plan с новой командой:

```text
ADVANCE_CONSTRUCTION_STAGE
```

Первая стадия:

```text
CREATE root item
ATTACH first parts
CONSUME stage materials
CREATE partial construct
```

Последующие стадии:

```text
ATTACH newly included parts
CONSUME stage materials
UPDATE construct snapshot
```

BuildPlan хранит исходные projections и cumulative allocations, поэтому before/after projections и checksum стадии детерминированы даже после restart.

#### BuildProcess

`ConstructionBuildProcess`:

- регистрирует BuildPlan;
- сверяет ghost с authoritative construct;
- проверяет expected stage index;
- проверяет required capabilities;
- строит deterministic C2A plan;
- исполняет его через C2B-compatible adapter;
- обновляет ghost только после authoritative success;
- поддерживает exact replay;
- восстанавливает progress после crash между C2B commit и ghost update;
- отклоняет divergence.

#### Builder agent

Минимальный `ConstructionBuilderAgent` исполняет следующий stage или весь BuildPlan через тот же `ConstructionBuildProcess`. Он не является отдельным способом строительства и не меняет Item Graph напрямую.

#### Persistence

`ConstructionBuildPlanStore` хранит immutable plans и recoverable ghost projections с checksum. Ошибочная загрузка не мутирует активное состояние.

### Контрольный vertical slice C3

Трёхстадийный стол:

1. `FOUNDATION`: столешница, две ножки, два крепежа;
2. `FRAME`: ещё две ножки, два крепежа;
3. `COMMISSIONING`: герметик и inspection capability.

Проверяются:

- ghost без массы и capabilities;
- PARTIAL snapshots;
- отсутствие operational capabilities до final stage;
- exact replay;
- capability gate;
- расход материалов ровно один раз;
- crash после authoritative commit;
- reconciliation;
- divergence rejection;
- persistence;
- builder agent.

### Acceptance C3

- C1 и C2A compatibility profiles проходят;
- C2B focused profile проходит на полном checkout;
- оба C3 теста проходят;
- C3 тесты включены в world regression;
- network/runtime regression проходит;
- world regression и main-scene CLI проходят;
- partial construct не имеет capabilities;
- ghost не имеет Item identity, массы и capabilities;
- crash recovery не расходует материал повторно;
- changed operation ID не может повторно завершить stage;
- divergent construct не маскируется ghost progress;
- `git diff --check` проходит.

**Статус:** IMPLEMENTED CANDIDATE.

## C4 — Composite Definition

- promotion завершённой сборки в повторно используемый composite;
- definition/instance separation;
- versioning;
- exposed ports;
- параметры;
- раскрытие внутреннего состава;
- BuildPlan generation из composite definition.

## C5 — Affordance и Capability Layer

- support surface;
- container;
- seat;
- climbable;
- workstation;
- mounting surface;
- агент использует пользовательский объект без зависимости от имени prefab.

## C6 — Mobile Construct

Наземный робот: корпус, колёса, моторы, батарея, контроллер, sensors и container. Проверяются rigid islands, joints, power/control graphs и partial failures.

## C7 — Spatial Construct

Небольшой дом: foundation, стены, дверь, комнаты, enclosure, энергия и рабочее место. Проверяются Space Graph и section activation.

## C8 — Fabrication Cell

Сборщик исполняет тот же BuildPlan, который может исполнять игрок или builder agent.

## C9 — Damage, Split, Repair

- ослабление и разрушение bonds;
- отделение частей;
- новые aggregate IDs;
- repair ghost;
- salvage policy;
- восстановление item parts.

## C10 — Parametric Members

Балки, панели, трубы, кабели, profiles и layered walls с вычисляемым расходом материала.

## C11 — Local Geometry Editing

Локальные CSG/SDF/voxel regions, отверстия, вырезы и surface processing без потери semantic parts и ports.

## C12 — Multiplayer Acceptance

Два графических клиента, contention, permissions, reconnect, replay, checksum convergence и отсутствие двойного расхода.

## C13 — Federated Large Constructs

Section aggregates, building coordinator, cross-section ports, spatial authority и compute-worker proposals.

## Gate C3 → C4

C4 начинается после внешнего PASS:

```text
Focused C1
Focused C2A
Focused C2B
Focused C3
Network/runtime regression
World regression including both C3 scenarios
Main-scene CLI
```
