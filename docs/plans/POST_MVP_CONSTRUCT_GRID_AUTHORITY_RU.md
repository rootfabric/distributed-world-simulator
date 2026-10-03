# Post-MVP — ConstructGrid, целостная authority и перенос крупных построек

Дата: 17 сентября 2026.
Статус: **DESIGN PROPOSAL / NOT ACTIVATED / NO CURRENT MVP SCOPE EXPANSION**.

Этот документ уточняет `POST_MVP_HIERARCHICAL_SEAMLESS_WORLDS_RU.md` и `POST_MVP_VOLUMETRIC_TOPOLOGY_DESIGN_RU.md`. Он не меняет принятые C1–C23 задним числом, не объявляет новый runtime owner и не расширяет текущий MVP. Цель — сформулировать единый контракт для домов, машин, станций и кораблей, которые могут пересекать границы пространственных authority.

Связанный обязательный consumer-contract для игроков, роботов и локальных объектов на движущихся grids: `POST_MVP_GRID_RESIDENT_BINDING_RU.md`.

## 1. Основная идея

Каждый канонический `ConstructAggregate` получает стабильный локальный **ConstructGrid**. Это не означает, что вся геометрия обязана состоять из одинаковых кубиков.

`ConstructGrid` — локальная система адресации и пространственный каркас конструкции:

```text
ConstructAggregate
  -> ConstructGrid / local frame
      -> parts / sections / parametric members
      -> compiled geometry / collision / rigid islands
      -> conservative spatial envelope
```

C10/C11 beams, panels, pipes, cables и произвольная локальная геометрия остаются допустимыми. Grid задаёт стабильные локальные координаты, индексацию и envelope, а не заменяет semantic parts или точную геометрию.

Отдельно:

```text
ConstructGrid != C16 snap-grid UI
ConstructGrid != World spatial partition grid
ConstructGrid != render mesh
ConstructGrid != physics solver island
ConstructGrid != ServerInstance
```

## 2. Контракт ConstructGrid

Концептуально нужны два разных состояния.

```text
ConstructGridDefinition {
    construct_id
    grid_id
    grid_revision
    local_basis
    local_origin
    optional_cell_size_or_addressing_policy
    local_bounds
    occupancy_or_envelope_digest
}
```

```text
ConstructPlacement {
    grid_id
    reference_frame_id
    world_from_grid_transform
    placement_revision
    transform_time_or_tick
}
```

Точные DTO/owner определяются при activation после аудита существующих C17/C18, WorldGraph и reference-frame contracts. Этот документ фиксирует семантику, а не разрешает создать второй Construct store.

### Неподвижные правила

```text
CG1  один construct имеет один стабильный root ConstructGrid;
CG2  grid identity не меняется от пересечения server seam;
CG3  локальные part/section coordinates не переписываются при server migration;
CG4  spatial seam сам по себе никогда не делит ConstructGrid;
CG5  ConstructGrid имеет одного canonical construct writer;
CG6  связанная физическая группа не получает второго physics writer из-за spatial overlap;
CG7  соседние authority могут хранить read-only projections/context;
CG8  canonical structural split, а не spatial seam, создаёт независимые child grids;
CG9  server placement является производным assignment и может меняться без смены construct/grid identity;
CG10 отсутствие target readiness сохраняет текущего owner; оно не разрешает частичный перенос.
CG11 proximity к grid не меняет player locomotion authority;
CG12 physical frame binding может сделать player/robot GRID_BOUND без изменения logical identity;
CG13 GRID_BOUND residents входят в migration closure whole-grid transfer;
```

## 3. Grid как единица пространственного охвата

Для текущей placement revision строится консервативный world-space envelope:

```text
E = transform(ConstructGrid.local_bounds, world_from_grid_transform)
```

Первая реализация может использовать OBB + conservative world AABB. Более точный sparse occupancy допускается позже, но **ложноположительная полная принадлежность запрещена**: лучше задержать перенос, чем решить, что grid целиком внутри B, когда его часть ещё находится в A.

Resolver возвращает не одного spatial owner для construct, а набор пересекаемых spatial partitions:

```text
coverage_set(grid) = { P_i | E intersects effective_region(P_i) }
```

Состояния:

```text
|coverage_set| == 1  -> GRID_FULLY_CONTAINED
|coverage_set| > 1   -> GRID_STRADDLING
```

`GRID_STRADDLING` не является ошибкой и не создаёт sharding автоматически.

## 4. Полное вхождение как условие обычной миграции

Регион B может стать обычным region-affine owner конструкции только когда **весь conservative envelope grid находится внутри effective(B)**.

```text
fully_contained(grid, B) == true
```

Для AABB первой версии это можно свести к проверке всех min/max границ. Для вращающегося OBB — проверить все углы OBB против target bounds либо использовать консервативный world AABB.

### Migration Core

Чтобы не мигрировать объект туда-сюда у границы, вводится производная область безопасного переноса:

```text
MigrationCore(B, G, margin)
```

Интуитивно target-region уменьшается на пространственный размер текущего grid-envelope плюс hysteresis margin. Для одномерного примера:

```text
B = [100, 200)
ship half-length = 20
margin = 5

full-containment core ~= [125, 175]
```

Пока root/pose grid не попадает в core, migration не требуется. Для меняющейся orientation core зависит от projected extents; первая реализация может вычислять eligibility по текущему pose и консервативным bounds.

Это configuration-space erosion / containment semantics, но production API не обязан использовать такой термин.

### Дополнительные условия migration

Полное вхождение необходимо, но недостаточно. Нужны также:

- target authority WARM/READY;
- compatible construct/physics schema;
- exact construct/grid/placement revisions;
- операция/physics barrier;
- terminal OperationId/result continuity;
- stale-source fencing;
- bounded migration budget;
- отсутствие запрещающего внешнего constraint/coupling state;
- согласованный reference-frame transform.

## 5. Что происходит, пока grid пересекает несколько серверных областей

Пример длинного корабля:

```text
Spatial:    AAAAAAAA | BBBBBBBB | CCCCCCCC
Ship grid:       =====================
Construct owner:          S
```

Корабль не делится на три writers. Текущий construct/physics owner `S` сохраняется, а A/B/C предоставляют нужный world context и получают read-only representation корабля.

```text
SPATIAL POINT -> exactly one spatial partition
CONSTRUCT GRID -> exactly one construct writer
PHYSICS GROUP -> at most one admitted physics writer
```

Это разные canonical states, поэтому присутствие корабля в пространстве B не означает, что B получает право изменить его структуру или интегрировать вторую authoritative physics copy.

Игрок или робот, находящийся рядом с grid, остаётся у своего world movement authority до подтверждённого physical-frame binding. Внешнее interaction с прибором маршрутизируется к construct owner без обязательного locomotion transfer. После `WORLD_BOUND -> GRID_BOUND` resident становится частью поддержанной grid simulation closure; подробный контракт находится в `POST_MVP_GRID_RESIDENT_BINDING_RU.md`.

## 6. Если grid больше spatial region

Если `MigrationCore(region, grid)` пуст, grid физически не может целиком оказаться в данном регионе.

Это не повод разрезать construct.

Допустимые варианты:

1. сохранить текущего owner независимо от spatial region;
2. назначить construct крупному/мобильному executor placement class;
3. перенести его между более крупными placement domains;
4. явно секционировать construct на независимые child constructs/grids, если это разрешает structural domain.

Запрещено:

```text
ship too large for region
=> split ship at region seam
```

Размер пространственного partition не должен задавать максимальный размер логического объекта.

## 7. Structural split создаёт новые grids

Только каноническое structural событие может изменить эту границу.

```text
Grid G
  -> structural break / accepted C9 split
      -> child construct G1
      -> child construct G2
```

После commit:

- G1/G2 получают stable identities и lineage;
- сохраняются parts/bonds/material provenance;
- вычисляются собственные local bounds/envelopes;
- сохраняются корректные mass/momentum/physics results согласно поддержанному domain contract;
- только после этого их placement/authority может расходиться.

До structural split пространственная граница не является линией разрушения.

GRID_BOUND residents после structural split должны быть однозначно reassigned к G1, G2 либо возвращены в WORLD_BOUND/free state; один resident не может оставаться canonical-bound одновременно к двум child grids.

## 8. Merge, docking и joints

Нельзя автоматически объединять grids из-за контакта.

Три разных случая:

```text
CONTACT ONLY
  -> grids остаются независимыми

JOINT / DOCKING RELATION
  -> grids могут оставаться независимыми;
     physics scheduler может временно совместить их в одну simulation group

CANONICAL STRUCTURAL MERGE
  -> создаётся/утверждается общий parent/root grid либо новый merged construct
     через отдельную authoritative transaction
```

Таким образом `ConstructGrid` и `PhysicsSimulationGroup` не являются одним объектом.

GRID_BOUND resident может перейти G1 -> G2 через explicit grid-to-grid binding handoff; docking сам по себе не делает все residents общими и не является implicit grid merge.

## 9. Статические большие здания

Дом или станция также имеют root ConstructGrid. Если grid пересекает несколько spatial regions, это не требует нескольких canonical copies.

Для действительно огромных объектов масштабирование допускает **явные section grids**:

```text
Station Root Grid
  -> Section Grid A
  -> Section Grid B
  -> Section Grid C
```

Sectioning является construction-domain решением со stable root identity и явными cross-section contracts. Оно не возникает автоматически из текущей карты серверов.

Это сохраняет совместимость с C17 `large buildings with section coordinator` и C18/C22 HLOD/streaming: runtime может распределять sections, не превращая визуальный LOD или spatial cell в новый source of truth.

## 10. Reference frames

ConstructGrid имеет собственные локальные coordinates, но его placement привязан к versioned external reference frame.

```text
part local -> ConstructGrid -> body/planet/space reference frame -> query frame
```

Server migration не должна автоматически менять ConstructGrid или preferred reference frame.

Для движущегося корабля grid может оставаться стабильным, пока меняется его `world_from_grid_transform`. Reference-frame migration и server-authority migration — разные операции.

GRID_BOUND resident хранит/использует grid-local pose/velocity semantics и при unbind должен быть корректно преобразован обратно в target world frame, включая движение/вращение grid.

## 11. Physics и collision

ConstructGrid упрощает ownership, но не решает распределённую физику автоматически.

Первый безопасный baseline:

- связанная physical simulation group имеет одного solver owner;
- spatial authorities поставляют versioned collision/environment context;
- соседние copies не коммитят второй impulse;
- сильносвязанные dynamic objects перед контактом либо co-locate для solve, либо используют отдельно доказанный coupling protocol;
- spatial seam не пересобирает rigid islands;
- GRID_BOUND locomotion не прыгает между spatial owners при ходьбе по одному mobile grid.

Construction уже компилирует geometry/collision/rigid islands из canonical data; Grid должен адресовать эту структуру, а не заменять её.

## 12. Migration whole-grid transaction

Обычный перенос конструкции выполняется как единый transaction scope:

```text
PRELOAD immutable assets/context
  -> COPY construct + grid + required physics state
  -> CATCH_UP revisions / operation results
  -> BARRIER at accepted simulation/operation cut
  -> verify target READY
  -> FENCE source writer
  -> durable assignment decision
  -> ACTIVATE target
  -> DRAIN old replicas/state
```

При успешном переносе неизменны:

```text
construct_id
grid_id
local part coordinates
structural identities
item identities
accepted operation results
resident logical identities
```

Меняются:

```text
authority/server assignment
authority epoch/incarnation
possibly placement/runtime caches
```

Если grid содержит GRID_BOUND residents, whole-grid migration closure включает их movement continuation, carrying/mount/constraint evidence и terminal operation watermarks. Hull не считается успешно перенесённым, если resident остаётся canonical-active на старом executor.

Если backend не умеет безопасно переносить требуемое physics state, grid остаётся у старого executor либо migration ждёт безопасного состояния. Нельзя компенсировать gap созданием второй active physics copy.

## 13. Обязательные тесты ConstructGrid

| ID | Сценарий | Критерий |
| --- | --- | --- |
| CG01 | 100-block static base полностью в A | coverage={A}; один owner |
| CG02 | Та же база пересекает A/B | coverage={A,B}; owner не делится |
| CG03 | Добавление/удаление блока меняет envelope через seam | migration не запускается от одного overlap |
| CG04 | Grid полностью входит B | eligible только после полного containment + readiness |
| CG05 | Колебание у seam | hysteresis; нет ping-pong migration |
| CG06 | 500m ship пересекает A/B/C | одна grid identity, один construct/physics writer |
| CG07 | Ship длиннее любого region | migration core empty; no forced split |
| CG08 | Поворот длинного ship около seam | coverage учитывает полный rotated/swept envelope |
| CG09 | Structural break на seam | только C9-like canonical split создаёт child grids |
| CG10 | Docking двух grids | contact/joint не означает implicit merge |
| CG11 | Canonical merge | новый/parent grid создаётся одной authoritative transaction |
| CG12 | Source crash во время whole-grid migration | recovery; at-most-one writer |
| CG13 | Lost reply / retry после migration | terminal result continuity; no duplicate effect |
| CG14 | Large station section grids | stable root; explicit sections; no spatial auto-split |
| CG15 | Terrain collision на другом spatial owner | один physics result; no duplicate impulse |
| CG16 | Reference-frame transform меняется | grid local coordinates стабильны; versioned placement |
| CG17 | Player B взаимодействует с ship A снаружи | interaction проходит, player остаётся WORLD_BOUND(B) |
| CG18 | Player B входит на mobile ship A | один WORLD_BOUND -> GRID_BOUND handoff, identities/session стабильны |
| CG19 | Player идёт по ship через A/B/C | locomotion не переключается по world seam |
| CG20 | Whole-grid migration с onboard residents | grid + residents transfer as one migration closure |
| CG21 | Player выходит на region C | GRID_BOUND -> WORLD_BOUND(C), world velocity корректна |

Подробная матрица resident cases: GR01–GR16 в `POST_MVP_GRID_RESIDENT_BINDING_RU.md`.

## 14. Как это встраивается в существующую Construction линию

Не переписывать принятый C17 задним числом. Переиспользовать его доказанные свойства:

```text
one aggregate -> one writer
owner routing
authority epoch / migration fence
read-only neighbor replicas
explicit migration
cross-zone split child
```

C16 snap `grid` остаётся UI/placement primitive. Новый ConstructGrid — post-MVP spatial/authority contract и должен быть связан с C10/C11 local geometry, C13 physics projection, C17 distributed authority, C18 streaming и C22/C24 compiled/HLOD representations без переноса ownership в presentation.

До отдельной activation этот workstream обозначается `CG` и не получает номер C25 автоматически.

## 15. Предлагаемая лестница CG

```text
CG0 Contract Audit
  existing Construction/WorldGraph/physics/player-movement capabilities

CG1 ConstructGrid Foundation
  stable grid identity + local placement + conservative envelope

CG2 Coverage / Containment
  world partition coverage_set + exact full-containment + MigrationCore

CG3 Straddling + Resident Binding Continuity
  static base + moving ship across A/B/C without authority split;
  WORLD_BOUND <-> GRID_BOUND; external interaction without locomotion transfer

CG4 Whole-Grid Migration
  full containment -> WARM -> barrier/fence -> whole-grid activate;
  GridResidentSet included in migration closure

CG5 Structural Split / Merge / Coupled Physics
  child grids only from canonical structural operations;
  docking/joints, temporary simulation groups, resident reassignment/grid-to-grid handoff

CG6 Scale / Recovery Acceptance
  large station/ship, many onboard residents, fault matrix, replay, sections, restart
```

## 16. Главный итоговый контракт

```text
EVERY CONSTRUCT HAS A STABLE LOCAL GRID.

WORLD PARTITIONS OWN SPACE.
CONSTRUCT AUTHORITY OWNS THE CONSTRUCT.
THESE ARE NOT THE SAME THING.

A GRID MAY STRADDLE MANY WORLD PARTITIONS.
STRADDLING DOES NOT SPLIT OWNERSHIP.

PROXIMITY DOES NOT MOVE A PLAYER TO THE GRID OWNER.
CROSS-AUTHORITY INTERACTION DOES NOT REQUIRE LOCOMOTION TRANSFER.

A RESIDENT MAY BECOME GRID_BOUND WHEN THE GRID BECOMES
THE PHYSICAL FRAME THAT DETERMINES RESIDENT MOTION.

GRID_BOUND RESIDENTS PARTICIPATE IN WHOLE-GRID MIGRATION CLOSURE.

NORMAL REGION-AFFINE MIGRATION IS ALLOWED ONLY AFTER
THE WHOLE GRID IS SAFELY CONTAINED IN THE TARGET REGION.

ONLY A CANONICAL STRUCTURAL SPLIT MAY CREATE
INDEPENDENT CHILD CONSTRUCT GRIDS.

SERVER PLACEMENT MAY CHANGE.
CONSTRUCT IDENTITY AND LOCAL GRID DO NOT.
```
