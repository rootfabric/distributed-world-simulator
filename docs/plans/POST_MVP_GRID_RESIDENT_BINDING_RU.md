# Post-MVP — WorldBound / GridBound и жители движущихся ConstructGrid

Дата: 17 сентября 2026.
Статус: **DESIGN PROPOSAL / NOT ACTIVATED / NO CURRENT MVP SCOPE EXPANSION**.

Этот документ дополняет:

- `POST_MVP_HIERARCHICAL_SEAMLESS_WORLDS_RU.md`;
- `POST_MVP_VOLUMETRIC_TOPOLOGY_DESIGN_RU.md`;
- `POST_MVP_CONSTRUCT_GRID_AUTHORITY_RU.md`.

Он фиксирует будущую семантику игроков, роботов и локальных физических объектов, которые входят на движущуюся постройку/корабль, пока сам `ConstructGrid` может пересекать несколько world spatial partitions.

Документ не создаёт новый runtime owner, не меняет текущий MVP и не является доказательством готовой реализации.

## 1. Основная проблема

Корабль может принадлежать construct/physics authority A и одновременно частично находиться внутри spatial region B.

```text
Spatial world:

AAAAAAAAAAAA | BBBBBBBBBBBB
             |
       =====================
            SHIP GRID
        construct owner A

                         player
                    world owner B
```

Игрок на B должен:

- видеть корабль;
- сталкиваться с его geometry;
- взаимодействовать с внешними приборами;
- при необходимости зайти на корабль;
- ходить внутри движущегося grid без разрыва physics;
- выйти на другой spatial region;
- сохранять identity, carrying и session continuity.

Нельзя решать это правилом «кто ближе к кораблю, тот автоматически переносится на его server»: proximity не является canonical physical relation и создаёт ping-pong authority.

## 2. Главный контракт

```text
PROXIMITY_DOES_NOT_TRANSFER_AUTHORITY
INTERACTION_DOES_NOT_IMPLY_LOCOMOTION_TRANSFER
PHYSICAL_FRAME_BINDING_MAY_TRANSFER_MOVEMENT_DOMAIN
GRID_BOUND_RESIDENT_FOLLOWS_GRID_SIMULATION_FRAME
UNBIND_RETURNS_RESIDENT_TO_WORLD_SPATIAL_AUTHORITY
```

Игрок следует тому simulation frame, который реально определяет его движение, а не ближайшему ServerInstance.

## 3. Два основных состояния mobility binding

### WORLD_BOUND

Игрок или другой подвижный объект движется относительно обычного world/reference frame.

```text
WORLD_BOUND {
    resident_id
    world_reference_frame_id
    spatial_partition_id
    movement_authority
    binding_revision
}
```

Обычный spatial resolver определяет region authority для locomotion.

### GRID_BOUND

Игрок физически находится в mobility frame конкретного `ConstructGrid`.

```text
GRID_BOUND {
    resident_id
    grid_id
    grid_placement_revision
    local_pose
    local_velocity
    movement_authority
    binding_revision
}
```

`movement_authority` в первой безопасной реализации co-located с physics executor связанной grid simulation group либо использует отдельно доказанный эквивалентный контракт.

`PlayerId`, `PlayerEntityId`, inventory identity и client WorldConnection от binding не меняются.

## 4. Когда binding НЕ происходит

Следующие события сами по себе не переводят resident в `GRID_BOUND`:

- proximity к construct;
- видимость construct;
- overlap interest/projection bounds;
- raycast/inspect;
- нажатие внешней кнопки;
- открытие двери;
- чтение панели;
- дистанционное управление;
- простой контакт без устойчивой physical relation.

До binding действие маршрутизируется как обычная cross-authority interaction:

```text
Player WORLD_BOUND(B)
  -> intent
  -> Construct authority A
  -> canonical device operation
  -> result/projection back to player
```

Перенос movement authority для такого действия запрещён как обязательное следствие interaction.

## 5. Основания для входа в GRID_BOUND

Первая реализация должна использовать явные, проверяемые причины.

### 5.1 Sustained support

Игрок устойчиво опирается на collision surface grid и его движение зависит от движения этой поверхности.

Одного краткого contact event недостаточно: нужны bounded support history/threshold и антидребезг.

### 5.2 Interior residency

Игрок находится внутри канонически/производно определённого interior/residency volume grid.

Это позволяет не разрывать binding при прыжке внутри каюты или краткой потере контакта с полом.

### 5.3 Mount / seat / control station

Явное mounting relation к креслу, турели, кабине, манипулятору или другому grid-bound anchor является сильным основанием binding.

### 5.4 Explicit physical constraint

Страховочный трос, магнитное крепление, лестница или иной поддержанный constraint может создавать binding согласно своему contract.

## 6. Mobility capability grid

Не каждая постройка обязана перехватывать locomotion.

Conceptual policy:

```text
provides_mobility_frame = false  -> обычная статическая постройка
provides_mobility_frame = true   -> корабль, поезд, машина, движущаяся платформа
```

Это capability, а не обязательно жёсткий object type.

Статическая база может позже стать mobile construct после поддержанного structural/state transition; тогда binding policy выводится из актуального canonical/compiled profile, а не из имени prefab.

## 7. Anti-chatter / residency hysteresis

Нельзя переключать authority при каждом кратком разрыве контакта.

Пример запрещённого поведения:

```text
касание палубы -> GRID_BOUND
прыжок         -> WORLD_BOUND
приземление    -> GRID_BOUND
```

Нужна residency/hysteresis policy:

- interior volume;
- bounded grace time после support loss;
- relative velocity limits;
- explicit exit boundary;
- mount/constraint state;
- versioned grid placement.

Hysteresis влияет на binding, но не меняет canonical world partition ownership.

## 8. GridResidentSet

Для каждого активного mobile grid нужен вычисляемый/реплицируемый набор физически связанных residents.

```text
GridResidentSet(grid_id) {
    bound_players[]
    mounted_items[]
    attached_robots[]
    local_loose_physics[]
    supported_local_processes[]
    resident_set_revision
}
```

Это не новый Item Graph и не второй canonical Construct store. Конкретный owner/материализация определяется при implementation audit.

`GridResidentSet` нужен как migration/physics closure: нельзя переносить ship grid и случайно оставить физически находящегося на нём игрока на старом executor.

## 9. WORLD_BOUND -> GRID_BOUND handoff

Reference flow:

```text
player WORLD_BOUND(B)
  -> approaches ship projection
  -> ship/context authority A becomes WARM for player movement handoff
  -> player establishes supported binding reason
  -> freeze/cut current movement state
  -> transform world pose/velocity into ConstructGrid local frame
  -> transfer movement continuation + carrying/binding evidence
  -> activate GRID_BOUND on grid physics executor
  -> retire old world movement writer
```

Required invariants:

```text
same PlayerId
same PlayerEntityId
same client WorldConnection
no respawn
no duplicate movement writer
carrying state preserved
binding reason and revisions explicit
```

Визуально для клиента это обычный шаг/прыжок на корабль без despawn/teleport.

## 10. GRID_BOUND simulation

Пока resident GRID_BOUND:

- локальная locomotion выражается в grid-local coordinates;
- внешний world transform получается из актуального `ConstructPlacement`;
- тесная ship/player collision решается в одной поддержанной simulation group либо эквивалентным доказанным coupling path;
- соседние spatial authorities получают read-only projections residents;
- world partition seam внутри корпуса не вызывает player authority handoff.

Для длинного корабля:

```text
Spatial:     AAAAA | BBBBB | CCCCC
ShipGrid:       ====================
Players:             p1 p2 p3

ship/grid physics owner: S
GRID_BOUND movement: S
spatial projections: A/B/C read-only as required
```

Игрок не прыгает между A/B/C, проходя по палубе одного mobile ConstructGrid.

## 11. Взаимодействие с приборами

До boarding:

```text
WORLD_BOUND(B) player
  -> cross-authority interaction
  -> Ship Construct owner A
```

После boarding:

```text
GRID_BOUND(ship) player
  -> same/collocated construct authority path where applicable
```

При этом Item/Construction command contracts, OperationId/revision/fencing и permissions не обходятся. Co-location является оптимизацией маршрута, а не новым mutation path.

## 12. GRID_BOUND -> WORLD_BOUND handoff

При выходе с mobile grid target spatial partition определяется по world-space position/trajectory и актуальной topology revision.

Перед unbind target world authority должен быть WARM/READY.

Критично сохранить world-space velocity.

Conceptually:

```text
v_world = v_grid_origin
        + omega_grid x r_local_world
        + R_grid * v_local
```

Точный reference-frame contract определяется существующей physics/frame архитектурой, но запрещено просто копировать local velocity как world velocity.

Reference flow:

```text
GRID_BOUND(ship)
  -> explicit exit / support+residency lost beyond hysteresis
  -> resolve target world spatial partition C
  -> prepare C
  -> transform local pose/velocity to world frame
  -> cut/fence grid-bound movement writer
  -> activate WORLD_BOUND(C)
  -> retire old grid-bound movement state
```

## 13. Whole-grid migration вместе с residents

Если сам ship grid проходит ordinary whole-grid migration A -> B, migration closure включает GRID_BOUND residents.

```text
WholeGridMigrationClosure {
    construct/grid identity
    required physics state
    GridResidentSet
    resident movement continuation
    carrying/mount/constraint evidence
    terminal operation results / watermarks
}
```

Нельзя считать whole-grid migration успешным, если hull активирован на B, а GRID_BOUND player/robot остаётся canonical-active на A.

Residents не обязаны менять logical player/item identities.

## 14. Что происходит при structural split корабля

Spatial seam никогда не делит residents сам по себе.

Если canonical structural split создаёт child grids G1/G2, каждый resident после commit должен быть детерминированно отнесён:

- к G1;
- к G2;
- либо переведён в WORLD_BOUND/free state, если больше не поддерживается ни одним child grid.

Нужны explicit split-time rules для mounts, interiors, support, loose physics и constraints. Нельзя оставить одного resident одновременно GRID_BOUND к двум child grids.

## 15. Docking двух mobile grids

Docking не означает автоматический canonical grid merge.

Возможны:

```text
G1 + G2
  -> independent grids
  -> joint/docking relation
  -> temporarily shared PhysicsSimulationGroup
```

Resident остаётся привязанным к своему grid, пока поддержанный transition не переводит его на другой grid.

Переход по стыковочному тоннелю:

```text
GRID_BOUND(G1)
  -> handoff overlap / ready G2
  -> GRID_BOUND(G2)
```

Canonical merge grids — отдельная structural transaction.

## 16. Failure semantics

Безопасность важнее бесшовности при аварии.

- stale grid owner не получает право продолжать canonical movement after fence;
- target не активирует resident без согласованного binding evidence;
- lost reply/retry не создаёт duplicate player entity или mount;
- crash во время handoff восстанавливается по durable decision/evidence;
- при неизвестном исходе resolver сначала устанавливает действующее authority state, а не угадывает по proximity;
- отсутствие готового target может дать bounded pause/backpressure, но не два movement writers.

## 17. Обязательные будущие тесты

| ID | Сценарий | Критерий |
| --- | --- | --- |
| GR01 | Игрок B проходит рядом с ship A | остаётся WORLD_BOUND(B), никакого proximity transfer |
| GR02 | Игрок B нажимает наружную кнопку ship A | cross-authority operation, movement owner остаётся B |
| GR03 | Игрок B становится на неподвижную палубу mobile-grid ship A | один WORLD->GRID handoff, identity/session стабильны |
| GR04 | Игрок прыгает на палубе | hysteresis, нет B<->A ping-pong |
| GR05 | Игрок входит в interior | остаётся GRID_BOUND без обязательного floor contact |
| GR06 | Игрок управляет прибором внутри ship | canonical construct operation, no duplicate mutation path |
| GR07 | Игрок идёт по 500m ship через A/B/C seams | movement owner не меняется из-за world seam |
| GR08 | Ship движется/вращается с player onboard | local/world transforms и velocity корректны |
| GR09 | Игрок спрыгивает с ship на region C | GRID->WORLD(C), world velocity включает движение/rotation ship |
| GR10 | Whole-grid migration A->B с 10 onboard players | hull + residents migrate as closure; no lost/duplicate players |
| GR11 | Crash на каждой фазе player binding | at-most-one movement writer, durable recovery |
| GR12 | Structural split ship под игроком | resident однозначно G1/G2/WORLD, never both |
| GR13 | Docking G1/G2, player проходит tunnel | explicit GRID(G1)->GRID(G2), no implicit grid merge |
| GR14 | Static base provides_mobility_frame=false | interaction works, locomotion remains spatial/world bound |
| GR15 | Lost reply/retry of mount/binding operation | exact replay/no duplicate mount or player state |
| GR16 | Ship projection stale on B | stale projection cannot authorize binding/interaction commit |

## 18. Место в post-MVP roadmap

Этот контракт является обязательным consumer `ConstructGrid`, а не отдельным глобальным foundation.

Рекомендуемое место:

```text
HS1 static volumetric topology
HS2 ConstructGrid foundation
HS3 reference frames / placement
HS4 straddling + WORLD_BOUND/GRID_BOUND mobility binding
HS5 whole-grid migration including GridResidentSet
HS6 cross-volume operations / large-object physics / grid-grid handoff
HS7 spatial + structural split/merge and resident reassignment
HS8 live acceptance with boarding, onboard movement and exit
```

Construction CG ladder уточняется так:

```text
CG1 ConstructGrid foundation
CG2 coverage/containment
CG3 straddling + GridResident binding
CG4 whole-grid migration + resident closure
CG5 structural split/merge/coupled physics + resident reassignment
CG6 scale/recovery acceptance
```

## 19. Финальный инвариант

```text
WORLD PARTITIONS OWN WORLD SPACE.
CONSTRUCT GRID OWNS ITS CONSTRUCT STATE.
PHYSICS GROUP OWNS ONE PHYSICAL SOLVE.

A PLAYER DOES NOT MOVE TO A SERVER BECAUSE OF PROXIMITY.
A PLAYER MAY BIND TO A MOBILE GRID WHEN THAT GRID BECOMES
THE PHYSICAL FRAME THAT DETERMINES THE PLAYER'S MOTION.

INTERACTION MAY CROSS AUTHORITIES WITHOUT MOVEMENT TRANSFER.

GRID_BOUND RESIDENTS MOVE WITH THE GRID'S SIMULATION CLOSURE.
EXITING THE GRID RETURNS THE RESIDENT TO THE RESOLVED WORLD AUTHORITY.
```
