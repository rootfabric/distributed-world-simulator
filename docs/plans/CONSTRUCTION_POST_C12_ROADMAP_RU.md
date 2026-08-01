# Карта развития строительной системы после C12

**Назначение документа:** каноническая карта этапов C13–C22.

**Точка входа:** после принятия `C12 — Multiplayer Construction Acceptance` базовое семантическое ядро строительства считается завершённым. Последующие этапы превращают его в отображаемый, физический, распределённый и масштабируемый runtime.

## Общая последовательность

```text
C12 Multiplayer Construction Acceptance
  ↓
C13 Runtime Geometry and Physics Projection
  ↓
C14 Structural Integrity and Load Paths
  ↓
C15 Executable Utilities and Machines
  ↓
C16 Construction Interaction and Editing UX
  ↓
C17 Distributed Construction Authority
  ↓
C18 Streaming, LOD and Dormant Constructs
  ↓
C19 Agent Construction and Automation API
  ↓
C20 Logistics and Construction Economy
  ↓
C21 Large-Scale Construction Acceptance
  ↓
C22 Production Hardening
```

## C13 — Runtime Geometry and Physics Projection

**Статус:** ACCEPTED.
**Рекомендуемая ветка:** `feature/c13-runtime-geometry-physics-projection`.

### Цель

Создать полностью удаляемую presentation/physics-проекцию из authoritative строительных данных.

```text
ConstructSnapshot
+ C10/C11 geometry state
+ C5/C6/C7 behavior profiles
        ↓
MeshInstance3D
CollisionShape3D
StaticBody3D / RigidBody3D
Navigation links
interactive nodes
```

### Обязательный scope

- mesh и collision для beam, panel, pipe, cable и layered wall;
- incremental rebuild только изменившихся частей;
- визуальный split/salvage после C9;
- runtime doors/openings C7;
- физическое движение C6;
- machine presentation C8;
- восстановление scene projection после reconnect и streaming;
- строгий запрет обратной записи presentation state в authoritative domain.

### Acceptance

- удаление всей runtime-сцены и её rebuild дают тот же checksum source state;
- presentation object не может попасть в DTO или metadata;
- локальный rebuild части не изменяет соседние item identities;
- split, repair и geometry edit корректно обновляют mesh/collision;
- headless сервер может работать без presentation.

### Реализованный C13 vertical slice

- strict JSON-safe `RuntimeProjectionRequest`, part/opening/construct descriptors;
- C10 primitive geometry и C11 semantic path segments;
- реальные `MeshInstance3D`, `CollisionShape3D`, `StaticBody3D`, `RigidBody3D`;
- collision shapes являются прямыми детьми `PhysicsBody3D`;
- C7 door state меняет transform closure part и collision;
- runtime openings создают NavigationLink3D и interaction anchors;
- C6 mobility state управляет rigid-body freeze;
- checksum-based incremental rebuild сохраняет неизменённые part nodes;
- `sync_world()` переносит C9 split parts между construct projections и удаляет отсутствующие constructs;
- runtime cache можно полностью удалить и восстановить из descriptors;
- presentation слой не изменяет `ItemProjection` или `ConstructSnapshot`.

## C14 — Structural Integrity and Load Paths

**Статус:** ACCEPTED.
**Рекомендуемая ветка:** `feature/c14-structural-integrity-load-paths`.

### Цель

Связать массу, геометрию, bonds и гравитацию в упрощённую, но детерминированную модель несущей способности.

```text
part mass + geometry + gravity
+ support conditions + bond strengths
        ↓
load graph
        ↓
stress/utilization
        ↓
degraded or broken bonds
        ↓
C9 damage/split
```

### Scope

- support nodes и load-bearing paths;
- распределение статической нагрузки;
- material/bond strength limits;
- buckling/overload в упрощённой модели;
- progressive collapse;
- far/dormant summary calculation;
- deterministic damage proposal, применяемый через C9 authority.

### Ограничение

Первая версия не является полноценным FEM. Нужен графовый инженерный уровень, пригодный для массовой симуляции.

### Реализованный C14 vertical slice

- strict checksum-pinned load cases;
- supports и scalar static loads;
- детерминированные shortest support paths;
- reactions, part/bond utilization и critical sets;
- safety factor, degraded capacity и simplified buckling limit;
- поэтапный progressive collapse с полным recompute;
- deterministic split identities и C9 DamageRequest;
- реальный C9 split/repair без клонирования ItemInstance;
- exact retry/replay и conflict detection через terminal ledger;
- rebuildable profile store и compact dormant summary.

## C15 — Executable Utilities and Machines

### Цель

Превратить C7 utility semantics в реальные потоки и runtime-процессы.

### Scope

- power generation, storage и consumption;
- water, gas/air, heat и data flows;
- topology, capacity, losses и priorities;
- отключение ветвей и load shedding;
- запуск/остановка C8 machines;
- разные simulation rates для active/summary/dormant;
- recovery незавершённых utility allocations.

```text
providers → topology → capacity allocation → consumers
```

### Acceptance

- conservation для потоков и энергии;
- deterministic allocation при равных входах;
- utility failure перекомпилирует capabilities;
- C8 job не продвигается без реально выделенного ресурса.

### Реализованный C15 vertical slice

- strict POWER/WATER/AIR/HEAT/DATA network DTO;
- source, consumer, storage и junction nodes;
- link capacity и последовательные losses;
- priority allocation и atomic minimum load shedding;
- deterministic route choice;
- storage discharge и surplus charging;
- execution profile/store/persistence/dormant summary;
- checksum-pinned machine utility lease;
- C8 reserve/progress/complete gate по фактическим allocations;
- work-unit capacity, exact replay и runtime recovery.

**Статус:** ACCEPTED.

## C16 — Construction Interaction and Editing UX

**Статус:** ACCEPTED.
**Коммит:** `a4376cd`.
**Рекомендуемая ветка:** `feature/c16-construction-interaction-editing-ux`.

### Цель

Дать игроку полноценный graphical workflow без обхода серверной authority.

### Scope

- placement ghost и snapping;
- ports, surfaces и semantic anchors;
- C11 control-point gizmos;
- размеры, профили и constraints;
- выбор parts/bonds/spaces/utilities;
- repair ghost и missing-material view;
- fabrication queue UI;
- причины authoritative rejection;
- multiplayer cursors/locks как advisory UI, а не authority.

```text
UI intent → C12 command → authoritative commit → replicated result
```


### Реализованный C16 vertical slice

- strict semantic snap targets: surface, port, grid и free;
- deterministic target selection по compatibility, priority, distance и ID;
- checksum-pinned placement request/solution и negative no-target result;
- реальный прозрачный `Node3D` placement ghost;
- C11 gizmo с `Marker3D` handles, grid и axis mask;
- build/repair material overlay с exact item identities;
- headless `Control` overlay с status/progress;
- C12-only command adapter без ссылок на domain processes;
- authoritative error code отображается UI без локальной подмены результата.

## C17 — Distributed Construction Authority

### Цель

Интегрировать constructs с горизонтальным пространственным серверным слоем.

### Базовая модель

```text
one aggregate → one authoritative writer
neighbor servers → read-only projections
migration → explicit transaction
```

### Scope

- owner server routing;
- authority epoch и migration fence;
- constructs на границах spatial cells;
- большие здания с section coordinator;
- cross-zone item/material movement;
- split с child aggregate на другой зоне;
- owner failure и takeover;
- command forwarding без двойного commit.

### Запрет

Небольшой aggregate не должен одновременно иметь нескольких writers.

### Реализованный C17 vertical slice

- strict authority records с owner server/cell, epoch, lease и checksum;
- owner routing существующих C12 commands без второго mutation path;
- migration fence, state handoff и terminal-operation transfer;
- cross-epoch exact replay после migration без двойного commit;
- read-only neighbor replicas и section projections;
- cross-zone C9 split child с отдельным owner record;
- checksum-pinned cross-zone item transfer authorization;
- lease-expiry takeover из актуальной replica;
- stale owner/epoch fencing;
- transactional registry/replica persistence.

**Статус:** ACCEPTED. Полный C17 regression подтверждён в составе C18 acceptance.
**Рекомендуемая ветка:** `feature/c17-distributed-construction-authority`.


## C18 — Streaming, LOD and Dormant Constructs

### Цель

Сделать возможными миллионы конструкций без постоянной полной активации.

### Activity levels

```text
DORMANT   — snapshot/checksum only
SUMMARY   — bounds, mass, capabilities, utility summary
SIMULATED — active domain processes
PRESENTED — mesh, collision, animation
```

### Scope

- lazy rebuild derived profiles;
- spatial streaming;
- construct/mesh LOD;
- physics sleep/unload;
- low-frequency utilities/fabrication;
- deterministic catch-up;
- сохранение queues и pending operations;
- memory/CPU budgets и eviction policy.

### Реализованный C18 vertical slice

- strict activity record с authority epoch и source checksum;
- interest/hysteresis/delayed dormancy policy;
- independent summary/simulation/presentation budgets;
- deterministic budget demotion и pinned-level atomic rejection;
- compact summary из C14/C15/capability/pending-work данных;
- LOD `FULL/SIMPLIFIED/IMPOSTOR/NONE`;
- lazy C13 runtime rebuild и eviction;
- bounded catch-up plans;
- owner-only simulation и read-only presentation;
- persistence без SceneTree.

**Статус:** ACCEPTED.
**Рекомендуемая ветка:** `feature/c18-streaming-lod-dormant-constructs`.

## C19 — Agent Construction and Automation API

### Цель

Позволить агентам планировать и выполнять стройку через те же контракты, что и игрок.

### Scope

- semantic construction goals;
- BuildPlan generation;
- bill of materials;
- поиск, заказ и изготовление деталей;
- доставка и reservation;
- staged execution;
- repair и salvage;
- tool/workspace requirements;
- permissions, budget и ownership;
- multi-agent contention.

### Контрольный сценарий

```text
цель: герметичное помещение
→ выбрать CompositeDefinition
→ вычислить parametric members
→ сформировать BOM
→ изготовить недостающее
→ доставить
→ построить
→ проверить C7 enclosure
```

### Реализованный C19 vertical slice

- strict goals `BUILD_COMPOSITE`, `REPAIR_CONSTRUCT`, `SALVAGE_CONSTRUCT`;
- deterministic BOM с точными ItemProjection bindings;
- C8 fabrication fallback с заранее назначенной output identity;
- formal procurement/block modes для unresolved BOM;
- атомарные reservation batches для items, tools, workspaces и budget;
- checksum-pinned work queue, step receipts и terminal replay;
- реальные C12 `BUILD_STAGE/APPLY_REPAIR/APPLY_DAMAGE` команды;
- C17 owner routing без локального mutation path;
- C9 repair по исходным item identities;
- persistence/restart без повторного fabrication или commit.

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c19-agent-construction-automation-api`.

## C20 — Logistics and Construction Economy

### Цель

Связать строительство с универсальным рынком и материальной экономикой.

### Scope

- BOM и procurement orders;
- склады и транспорт;
- production contracts;
- подрядчики;
- стоимость труда и энергии;
- salvage market;
- repair orders;
- аренда оборудования;
- supply-chain shortages;
- производственные цепочки между C8 cells.

## C21 — Large-Scale Construction Acceptance

### Цель

Доказать масштабируемость на сценариях, близких к целевому миру.

### Нагрузочные профили

- тысячи одновременных BuildPlan;
- десятки тысяч constructs;
- миллионы item-backed parts;
- массовое damage/collapse;
- сотни fabrication cells;
- рой строительных агентов;
- reconnect storms;
- authority migration;
- server restart и event replay;
- длительный soak.

### Контрольные миры

```text
городской квартал
промышленный комплекс
лунная база
рой автоматических строителей
массовое повреждение и восстановление
```

## C22 — Production Hardening

### Цель

Закрыть эксплуатационные риски перед production-использованием.

### Scope

- schema migrations;
- backward-compatible saves;
- rolling upgrades;
- replay старых operations;
- observability и metrics;
- audit и permission security;
- rate limits;
- DTO fuzzing;
- corruption recovery;
- chaos testing;
- soak tests;
- release/runbook documentation.

## Приоритеты

Критический путь после C12:

```text
C13 presentation/physics
→ C17 distributed authority
→ C18 streaming/LOD
```

C14–C16 можно частично вести параллельно. C19–C20 следует начинать после устойчивого C17/C18, чтобы агенты и экономика строились сразу поверх распределённой authority.

## Общие инварианты C13–C22

Ни один этап не принимается, если он:

1. создаёт вторую identity детали;
2. делает mesh/physics authoritative;
3. обходит C2B/M0 transaction boundary;
4. допускает несколько writers одного aggregate без migration protocol;
5. теряет exact replay после reconnect/restart;
6. публикует capability, не доказанную текущим authoritative state;
7. нарушает checksum convergence клиентов и сервера.

## C20 — реализованный vertical slice

C20 формализует construction economy: procurement, warehouse reservations, routes, escrow, contractors, salvage и C8 production chains. Главная граница остаётся прежней: economy планирует и координирует, но реальные предметы изменяются только через Item Graph/C8/C2B, а agent workflow — через C19.
