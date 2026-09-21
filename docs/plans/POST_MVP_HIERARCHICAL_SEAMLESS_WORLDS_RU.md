# Post-MVP — объёмная бесшовность, ConstructGrid и иерархия областей

Статус: **POST-MVP ROADMAP AMENDMENT / NOT ACTIVATED / NO CURRENT MVP SCOPE EXPANSION**.
Уточнение R4: 17 сентября 2026.

Подробные решения:

- [объёмная топология, размещение и безопасное переразбиение](POST_MVP_VOLUMETRIC_TOPOLOGY_DESIGN_RU.md);
- [ConstructGrid, целостная authority и перенос крупных построек](POST_MVP_CONSTRUCT_GRID_AUTHORITY_RU.md);
- [WORLD_BOUND / GRID_BOUND и GridResidentSet](POST_MVP_GRID_RESIDENT_BINDING_RU.md).

Этот план определяет первое крупное направление после принятия `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`. Он не является текущим Work Order, не расширяет acceptance первого MVP и не разрешает post-MVP runtime mutation. До принятия PR в main это предложение, не канонический scheduler.

R4 уточняет прежний HS-план: «вложенные миры» означают одно непрерывное пространство с объёмными участками ответственности. Крупные конструкции не разрезаются server seam: каждая постройка имеет стабильный локальный `ConstructGrid`, который может пересекать несколько spatial partitions и сохранять одного construct/physics writer до отдельного безопасного переноса. Игрок/робот не переносится к owner grid по proximity: locomotion меняет domain только при подтверждённом physical-frame binding `WORLD_BOUND <-> GRID_BOUND`.

## 1. Цель

Перейти от простого плоского seam к системе, где одновременно выполняются четыре свойства:

1. каждая точка объявленного world-space однозначно относится к одному spatial partition;
2. каждая каноническая постройка имеет стабильный локальный ConstructGrid и единственного writer;
3. server placement может меняться независимо от spatial/construct identity;
4. resident может физически войти на mobile ConstructGrid и следовать его simulation frame без перепривязки по world seams.

Эталонное описание пространства:

```text
Space
  -> Planet
      -> Surface POI
          -> Cave / Basement / Dungeon
```

Эталонный крупный объект:

```text
Spatial partitions:   AAAAAAAA | BBBBBBBB | CCCCCCCC
Ship ConstructGrid:        =====================
Construct/physics owner:             S
```

Эталонный resident route:

```text
WORLD_BOUND(B)
  -> external interaction with ship A, no movement transfer
  -> board mobile ship
  -> GRID_BOUND(ship)
  -> walk across A/B/C while remaining grid-bound
  -> exit onto region C
  -> WORLD_BOUND(C)
```

Игрок проходит `Space -> Planet -> POI -> Dungeon -> POI -> Planet -> Space` обычным движением. Корабль, база или станция могут пересекать spatial seam без автоматического structural split, teleport или смены object identity.

## 2. Основной контракт

```text
ONE_CONTINUOUS_WORLD_SPACE
ONE_CLIENT_WORLD_CONNECTION
STABLE_PLAYER_AND_ENTITY_IDENTITIES
NO_NORMAL_GAMEPLAY_RECONNECT_OR_RESPAWN

EXACTLY_ONE_SPATIAL_PARTITION_PER_POINT_IN_DECLARED_COVERAGE
AT_MOST_ONE_ADMITTED_WRITER_PER_CANONICAL_STATE
CHILD_DELEGATION_SUBTRACTS_FROM_PARENT_EFFECTIVE_REGION

EVERY_CONSTRUCT_HAS_STABLE_LOCAL_GRID
SPATIAL_SEAM_NEVER_IMPLICITLY_SPLITS_CONSTRUCT_GRID
GRID_STRADDLING_MAY_SPAN_MULTIPLE_SPATIAL_PARTITIONS
WHOLE_GRID_CONTAINMENT_REQUIRED_FOR_NORMAL_REGION_AFFINE_MIGRATION
CANONICAL_STRUCTURAL_SPLIT_CREATES_CHILD_GRIDS

PROXIMITY_DOES_NOT_TRANSFER_PLAYER_AUTHORITY
INTERACTION_DOES_NOT_REQUIRE_LOCOMOTION_TRANSFER
PHYSICAL_FRAME_BINDING_MAY_CREATE_GRID_BOUND_RESIDENT
GRID_BOUND_RESIDENT_FOLLOWS_GRID_SIMULATION_FRAME
WHOLE_GRID_MIGRATION_INCLUDES_GRID_BOUND_RESIDENT_CLOSURE
UNBIND_RETURNS_RESIDENT_TO_RESOLVED_WORLD_AUTHORITY

SPATIAL_PARTITION != SERVER_PLACEMENT
CONSTRUCT_GRID != WORLD_PARTITION_GRID
CONSTRUCT_GRID != PHYSICS_ISLAND
REFERENCE_FRAME != SERVER_OWNER
SEMANTIC_ZONE != OWNERSHIP_REGION

CANONICAL_ITEMS_AND_CARRYING_PRESERVED
VERSIONED_TOPOLOGY_ASSIGNMENT_GRID_BINDING_AND_FRAME_EVIDENCE
STALE_OWNERSHIP_CANNOT_AUTHORIZE_CANONICAL_COMMIT
```

На barrier/failure допустима временная недоступность writer, но не split-brain. Ноль доступных writers не означает дыру в topology и не возвращает child scope родителю автоматически.

## 3. Слои и существующие foundations

Разделять:

```text
reference frames / coordinates
semantic places and zones
canonical world spatial partitions
ConstructGrid / construct ownership
resident movement binding (WORLD_BOUND / GRID_BOUND)
physics simulation groups
server placement / authority epochs
interest / WARM / projections
```

Semantic и visibility overlaps допустимы. Эффективные spatial ownership-области не пересекаются. ConstructGrid может пересекать их и при этом оставаться одним canonical construct.

Переиспользовать WorldGraph, Directory/AUTHORITY, existing spatial identities, Edge Gateway, SM1, MW9/MW10, Item Graph и Construction owners. Не создавать второй Construction store, Item Graph, player identity store, physics truth или routing foundation.

Начальная spatial topology — статические half-open AABB и вложенные исключения. Начальный ConstructGrid — стабильный local frame + conservative envelope поверх существующих C10/C11 geometry semantics. Grid не требует, чтобы parametric members стали кубическими вокселями.

## 4. Лестница HS1–HS8

### HS1 — Static Volumetric Topology

Собрать объявленное покрытие Planet/POI/Cave с явным остатком родителей.

Доказать:

- точное покрытие без дыр и authoritative overlap;
- half-open faces/edges/vertices;
- child subtraction из effective(parent);
- запрет sibling ownership overlap;
- fail-closed при stale/partial topology cache;
- несколько spatial partitions могут быть размещены на одном ServerInstance.

Тесты включают два подвала один над другим, semantic overlap без смены owner и invalid ownership overlap с отказом публикации.

### HS2 — ConstructGrid Foundation and Containment

Связать accepted Construction semantics с post-MVP spatial topology без переписывания C17.

Доказать:

```text
ConstructAggregate -> stable ConstructGrid
ConstructGrid -> local coordinates + conservative envelope
placement -> versioned world/reference-frame transform
coverage_set(grid) -> all intersected spatial partitions
```

Обязательные случаи:

- 100-block база полностью в A;
- та же база пересекает A/B;
- длинный корабль пересекает A/B/C;
- поворот grid меняет coverage_set корректно;
- grid больше отдельного spatial region;
- C10/C11 parametric geometry сохраняется и не заменяется block-only truth.

`GRID_STRADDLING` является нормальным состоянием. В нём construct сохраняет одного canonical writer; seam не создаёт child constructs.

Ввести и проверить `MigrationCore(target, grid, margin)` или эквивалентную full-containment/hysteresis semantics. Если core пуст, данный grid не обязан мигрировать в этот region.

### HS3 — Coordinates, Reference Frames and Grid Placement

WorldAddress и ConstructPlacement связывают instance/space, reference frame, transform, time/tick и revisions.

Доказать:

- position/orientation conversion без скачка;
- применимую velocity semantics;
- ConstructGrid local coordinates стабильны при server migration;
- render-origin shift не меняет canonical address;
- reference-frame transition и server-authority migration — разные операции;
- moving/rotating ConstructGrid корректно пересчитывает conservative envelope/coverage.

Отдельная frame на каждый server запрещена как следствие placement.

### HS4 — Static Seam, Straddling and Resident Binding Continuity

Запустить реальные authority-процессы, Gateway и два клиента.

Сначала доказать ordinary player/carrying seam через заранее заданные соседние и вложенные объёмы. Затем доказать крупный ConstructGrid, который физически пересекает A/B/C **без construct migration**.

Добавить mobility binding proof:

```text
WORLD_BOUND(B)
 -> approach ship A: no proximity transfer
 -> external device interaction: still WORLD_BOUND(B)
 -> supported/interior/mount binding
 -> GRID_BOUND(ship)
 -> walk/jump across world seams without B/A/C locomotion ping-pong
 -> exit onto C
 -> WORLD_BOUND(C)
```

```text
same client WorldConnection
normal reconnects = 0
respawns = 0
teleport used as seam substitute = false
construct_id/grid_id stable
construct writer count = 1
physics writer count <= 1
player movement writer count <= 1
PlayerId / PlayerEntityId stable
carrying preserved
```

Spatial authorities заранее готовят нужные collision/environment/projection data. WARM/interest overlap не получает write authority. Неготовность контекста не интерпретируется как пустое пространство. GRID binding использует explicit reason/revision и hysteresis; прыжок внутри/на палубе не должен вызывать authority ping-pong.

### HS5 — Whole-Grid Migration + Resident Closure

После HS2–HS4 разрешить отдельный whole-grid migration gate.

Обычная region-affine migration допускается только когда:

- весь conservative grid envelope находится внутри target effective region;
- выполнена hysteresis/dwell policy;
- target WARM/READY;
- exact grid/construct/physics revisions совместимы;
- нет запрещающего external coupling state;
- operation/physics barrier определён;
- stale source writer может быть fenced.

Если есть GRID_BOUND residents, migration closure включает их locomotion continuation, local pose/velocity, carrying/mount/constraint evidence и operation watermarks.

Маршрут:

```text
PRELOAD
 -> COPY/CATCH_UP grid + physics + residents
 -> BARRIER
 -> READY
 -> FENCE SOURCE
 -> DURABLE ASSIGNMENT DECISION
 -> ACTIVATE TARGET
 -> DRAIN/CLEANUP
```

После migration неизменны `construct_id`, `grid_id`, local part coordinates, player/entity/item identities и accepted operation results.

Проверить migration в обе стороны, lost reply/retry, source/target crash, 10+ onboard residents и объект, который долго находится у seam без ping-pong migration.

### HS6 — Cross-Volume Operations and Large-Object Physics

Проверить реальные операции, когда world-space, construct ownership и resident movement binding различаются.

Обязательные сценарии:

- бур/взрыв пересекает несколько spatial partitions;
- корабль имеет один physics owner, но контактирует с terrain другого spatial owner;
- тяга/действие на одной стороне длинного construct и collision на другой дают один physics result;
- соседняя replica не коммитит второй impulse;
- два dynamic grids при сильной связи не получают два независимых solver результата;
- WORLD_BOUND player взаимодействует с construct другого owner без locomotion transfer;
- GRID_BOUND player взаимодействует внутри ship через тот же canonical Item/Construction path;
- docking G1/G2 допускает explicit GRID_BOUND(G1)->GRID_BOUND(G2) handoff без implicit grid merge.

Использовать MW9/MW10, CWIP и Item/Construction transaction/recovery contracts после аудита API. Пространственное разложение footprint не заменяет атомарность.

Первый baseline для strong coupling: co-location/one simulation-group owner либо отдельно доказанный coupling protocol; network seam сам не является physics constraint.

### HS7 — Controlled Spatial Split/Merge + Construct Structural Split/Recovery

Разделить два разных вида split.

**Spatial split:**

```text
R -> R_left + R_right
```

меняет карту world partitions/placement и не разрезает ConstructGrid.

**Structural split:**

```text
ConstructGrid G
 -> canonical C9-like structural break
 -> child grid G1 + child grid G2
```

только после canonical structural transaction допускает независимое размещение частей.

При structural split GRID_BOUND resident должен быть однозначно reassigned к G1, G2 либо WORLD_BOUND/free state. Одновременный canonical binding к двум child grids запрещён.

Подэтапы:

| Подэтап | Обязательное доказательство |
| --- | --- |
| HS7.A Placement | migrate world partition без смены геометрии; несколько partitions на одном server |
| HS7.B Spatial split/merge | parent/child exclusions сохранены; constructs не режутся seam |
| HS7.C Construct split/merge | child grids только из canonical structural operations; docking/contact не является implicit merge |
| HS7.D Resident reassignment | GRID_BOUND residents детерминированно follow child grid или unbind |
| HS7.E Durable cutover | snapshot/catch-up, barrier, fence, durable decision, activation, cleanup |
| HS7.F Fault matrix | crash/restart, stale process/route, lost reply, concurrent edit, forward recovery |

Использовать VT01–VT24, CG01–CG21 и GR01–GR16 из design-документов как вход будущего test plan.

### HS8 — Four-Level Live Composition Acceptance

Финальный ограниченный стенд:

```text
2 clients
Gateway
Space / Planet / POI / Cave authorities
100-block boundary construct
long moving ConstructGrid / ship fixture
onboard GridResidentSet
```

Пройти полный пространственный маршрут и одновременно доказать:

- player/item/carrying continuity;
- dig/build operations;
- ConstructGrid straddling without split;
- WORLD_BOUND external interaction without locomotion transfer;
- boarding WORLD_BOUND -> GRID_BOUND;
- onboard walk/jump across multiple world seams;
- GRID_BOUND -> WORLD_BOUND(C) exit with correct world velocity;
- один whole-grid migration с onboard residents после полного containment;
- spatial split/merge без разрезания construct;
- canonical structural split с child grids и resident reassignment;
- recovery/fencing/replay;
- bounded WARM/projection cleanup.

Нужны exact HEAD/TREE evidence, relevant regressions, Project Control и independent review/verification по активированному Harness-контракту. Документы и модели не являются acceptance.

## 5. Что остаётся за пределами первого этапа

Не включаются автоматически:

- полный WORLDGEN1;
- production ECO/FABRIC;
- новые global owners;
- arbitrary distributed iterative physics solver;
- automatic placement/Kubernetes;
- тысячи игроков;
- implicit spatial sharding любого construct;
- доказательство всех moving-frame/orbital cases.

Если grid больше region, допустим pin/крупный executor/более крупный placement domain. Автоматически разрезать объект запрещено.

## 6. Место в post-MVP развитии

```text
CURRENT MVP ACCEPTED
  -> HS1: static volumetric world topology
  -> HS2: ConstructGrid + coverage/full containment
  -> HS3: reference frames + grid placement
  -> HS4: seamless straddling + WORLD_BOUND/GRID_BOUND binding
  -> HS5: whole-grid migration + GridResidentSet closure
  -> HS6: cross-volume operations / large-object physics / grid-grid handoff
  -> HS7: controlled spatial + structural split/merge/resident recovery
  -> HS8: live multi-level acceptance
  -> larger world / scale / placement optimization later
```

Construction integration использует отдельную плановую лестницу CG0–CG6 из `POST_MVP_CONSTRUCT_GRID_AUTHORITY_RU.md`; resident-binding acceptance — GR01–GR16 из `POST_MVP_GRID_RESIDENT_BINDING_RU.md`. Это не номер C25 и не переоткрытие accepted C17. Конкретная activation должна сначала сверить live Construction/player movement frontier и capabilities main.

WORLDGEN1, NX/RF, контент и ECO/FABRIC остаются отдельными направлениями через явные consumer contracts. Этот roadmap не переименовывает P8 и не меняет заявленную независимость P8/RF.

## 7. Activation и состояние доказательств

Реализация разрешается только после принятия `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`, закрытия текущего MVP Work Order, определения exact accepted base, отдельного post-MVP activation/epoch и bounded Work Order.

Перед исполнением сверить настоящий status существующих owners. Specification candidate не равен runtime acceptance. Неизвестный API фиксируется как gap, не восполняется demo-only store/координатором.

Уточнение R4 не изменяет текущий MVP6 или его acceptance. Документы HS/CG/GR — направление будущей реализации, не второй scheduler.
