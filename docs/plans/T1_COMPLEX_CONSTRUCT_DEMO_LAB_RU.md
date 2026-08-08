# T1 — Complex Construct Demo Lab

**Дата фиксации:** 2026-08-08
**Ветка:** `feature/t1-complex-construct-demo-lab`
**Статус:** IMPLEMENTATION READY / PRE-T0 EXPERIMENTAL
**База:** актуальный `main` после принятого C24 GPU-ready proxy mesh backend

## 1. Назначение

Эта ветка собирает первый сложный игровой объект, который одновременно проверяет уже построенные Item, Construction, Network, Utilities, Damage, Streaming и HLOD границы не в изолированных vertical slices, а в одной живой demo-сцене.

Контрольный объект — небольшая лунная инженерная база (`Lunar Engineering Outpost`).

Цель не в том, чтобы сразу построить максимально крупную станцию. C21/C22/C24 уже отдельно доказали масштабируемость и 10 000-part representation path. Новый lab должен доказать **композицию**:

```text
Item Graph
+ ConstructSnapshot
+ BuildPlan / CompositeDefinition
+ capabilities / affordances
+ rooms / openings / utilities
+ fabrication / machines
+ damage / split / repair
+ structural integrity
+ runtime geometry / physics
+ multiplayer authority
+ streaming / HLOD
= один работающий сложный объект
```

## 2. Положение относительно общей roadmap

Формальный порядок остаётся:

```text
Network Minimum ACCEPTED
        ↓
T0 Item / Playground ACCEPTED
        ↓
T1 Construction
        ↓
T2 Construction Scale
```

Но разработку этой ветки разрешено начинать до формального T0 acceptance, потому что сетевой first-playable minimum уже достигнут архитектурно, C12/C17/C18/C24 приняты, а оставшийся network feel/tuning не должен блокировать gameplay labs.

Правило gate:

```text
можно разрабатывать T1A/T1B до T0;
нельзя объявлять T1 ACCEPTED до T0 ACCEPTED.
```

Если lab выявляет canonical correctness defect — duplication, item loss, divergent state, broken authority, non-idempotent operation, reconnect loss — это блокер и он возвращается в соответствующий domain/network слой.

Если выявляется только visual lag, interpolation/prediction feel, draw-call debt или asset polish — работа над lab продолжается параллельно.

## 3. Контрольный объект

### Lunar Engineering Outpost

Минимальная смысловая структура:

```text
OUTPOST
├── HABITAT
│   ├── walls / floor / roof
│   ├── door / window
│   ├── table / seat
│   ├── storage container
│   └── light
├── AIRLOCK
│   ├── inner door
│   ├── outer door
│   └── opening / room boundary
├── WORKSHOP
│   ├── workbench
│   ├── fabricator/CNC
│   ├── tool storage
│   └── console
├── UTILITY ROOM
│   ├── generator
│   ├── battery
│   ├── power junction
│   ├── data junction
│   └── air/utility connection
└── EXTERIOR
    ├── cargo platform
    ├── rover parking/mount point
    └── external container
```

Объект должен быть одним authoritative construct/согласованным набором constructs по уже существующим правилам aggregate ownership, а не набором специальных demo-only Node3D.

## 4. Неизменяемые архитектурные правила

1. `ConstructSnapshot` и Item Graph остаются canonical truth.
2. SceneTree, mesh, collision presentation, shaders и imported assets не становятся authority.
3. Все изменения конструкции проходят через существующий authoritative construction operation path.
4. Все реальные item перемещения/расходы проходят через Item Graph transaction boundary.
5. Один и тот же operation ID не может применить изменение дважды.
6. Offline/local, automated test и network server используют одну domain semantics.
7. HLOD/streaming не меняют identity, состав или checksum authoritative объекта.
8. Interactive part сохраняет identity независимо от того, показан ли его near mesh, simplified representation или только distant shell.
9. Presentation rebuild разрешено полностью удалить и восстановить из canonical state.
10. Новая demo-сцена не получает альтернативный RPC-driven mutation path.

## 5. Разделение этапа

Текущий T1 делится на две подстадии:

```text
T1A — Complex Construct Assembly Demo
        ↓
T1B — Complex Construct Composition / Failure Demo
        ↓
T2  — Construction Scale
```

### T1A

Доказать, что сложный объект можно собрать, загрузить, использовать двумя игроками и отображать на разных дистанциях.

### T1B

Доказать, что изменение одной части корректно распространяется на независимые facets: items, structure, utilities, capabilities, physics, HLOD и multiplayer convergence.

### T2

После композиционного acceptance увеличивать размер объекта без изменения domain architecture.

## 6. Масштабные профили D0–D3

### D0 — Composition Skeleton

Цель: 50–100 semantic parts.

Состав:

- одна герметичная комната;
- одна дверь;
- одно окно;
- один контейнер;
- generator;
- battery;
- lamp;
- console;
- минимальная power/data связь.

Acceptance D0:

- сцена строится только из authoritative descriptors;
- offline и graphical paths дают один canonical construct checksum;
- container реально открывается через Item system;
- door interaction проходит через capability/affordance;
- generator/battery/lamp дают минимальный utility chain;
- runtime projection можно удалить и rebuild без изменения source state.

### D1 — Playable Outpost

Цель: 300–500 semantic parts.

Добавить:

- habitat;
- airlock;
- workshop;
- storage;
- utility room;
- несколько containers;
- fabricator;
- workbench;
- несколько lights;
- power/data/air topology;
- exterior cargo platform;
- rover parking/mount point.

Acceptance D1:

- два клиента входят в одну сцену;
- оба видят одинаковые construct/item revisions;
- можно переносить предметы между backpack и storage;
- можно открыть/закрыть двери;
- utility consumers реагируют на доступность provider;
- fabricator получает capability/utility gate;
- reconnect восстанавливает authoritative object state;
- near/mid/far presentation переключается без изменения canonical state.

### D2 — Composition Stress

Цель: 1 000–2 000 semantic parts.

Добавить:

- несколько structural sections;
- повторяющиеся декоративные/utility детали;
- несколько rooms;
- локальный damage/removal;
- structural load paths;
- utility failure propagation;
- dirty-section rebuild;
- HLOD transitions под движущимся observer.

Acceptance D2:

- локальное изменение не требует полного rebuild всей базы;
- structural damage вызывает только допустимые C9/C14 последствия;
- utility break не разрушает несвязанные facets;
- обе стороны multiplayer сходятся к одному revision/checksum;
- reconnect после damage восстанавливает тот же результат;
- renderer не требует тысячи independent heavy nodes там, где уже возможны compiled proxies/instance batches.

### D3 — Construction Scale

Цель: 10 000+ semantic parts, затем при необходимости 100 000.

D3 относится уже к T2.

Основная задача — заменить синтетический scale fixture реальной сложной базой, сохранив уже доказанные C22/C24 свойства:

- DISTANT_SHELL заменяет дочернюю presentation;
- section HLOD;
- content-addressed proxy reuse;
- bounded GPU/resource cache;
- incremental invalidation;
- network interest не требует передачи всех child identities дальнему наблюдателю.

## 7. T1A — пункты реализации

### T1A.0 — Baseline and fixture contracts

- зафиксировать базовый main/C24 head;
- создать отдельную demo scene и fixture builder;
- не менять production Item/Construction contracts без отдельного review;
- добавить deterministic fixture seed/IDs;
- добавить machine-readable demo manifest;
- определить D0/D1 expected part counts, room IDs, utility IDs, item IDs и initial checksums.

### T1A.1 — Part Visual Profile / Asset Adapter

Ввести presentation-only catalog boundary:

```text
PartDefinition
    ↓ visual_profile_id
PartVisualProfile
├── representation_class
├── source mesh/scene reference
├── material family
├── bounds / pivot
├── grid footprint
├── collision presentation profile
├── near/mid/far representation profile
└── batching policy
```

Минимальные `representation_class`:

```text
STRUCTURAL_CELL
STATIC_COMPLEX_MESH
INSTANCED_MESH
INTERACTIVE_FIXTURE
```

Правила:

- catalog не входит в canonical construct checksum;
- замена visual asset не меняет Item/Construct identity;
- headless сервер способен работать без загрузки mesh assets;
- demo может сначала использовать primitive placeholders, затем Quaternius/другие assets без изменения domain.

### T1A.2 — D0 Outpost Builder

- собрать deterministic CompositeDefinition/BuildPlan для D0;
- построить structural shell;
- создать room/opening semantics;
- подключить door, container, generator, battery, lamp, console;
- дать сцене offline/local launch path;
- дать runtime rebuild/reset command для проверки projection purity.

### T1A.3 — Item integration

- backpack → container;
- container → backpack;
- loose item pickup/drop около базы;
- stack transfer;
- item-backed installed fixture identity;
- uninstall/remove там, где существующий construction contract это разрешает;
- проверить, что visual fixture не создаёт вторую item identity.

### T1A.4 — Utility and machine composition

Минимальная сеть:

```text
generator → battery/junction → lamp
                         └──→ console
                         └──→ fabricator
```

Проверить:

- provider availability;
- consumer allocation;
- machine blocked без utility lease;
- capability refresh после utility state change;
- utility profile rebuild из authoritative construct.

### T1A.5 — Multiplayer demo

- Player A + Player B;
- один authoritative server;
- один и тот же outpost identity;
- item operations;
- door operations;
- construction operation;
- machine interaction;
- reconnect одного клиента;
- canonical convergence после каждого scripted milestone.

До formal T0 acceptance этот профиль считается experimental validation, а не T1 acceptance.

### T1A.6 — Runtime inspector and telemetry

Demo HUD/diagnostics должны показывать минимум:

```text
construct_id
construct revision/checksum
item aggregate revision
part count
active interactive parts
activity level
HLOD/detail mode
active runtime nodes
proxy artifacts
mesh cache hits/misses
estimated GPU bytes
utility summary
structural summary
last operation ID/result
```

Debug UI является presentation-only.

## 8. T1B — пункты реализации

### T1B.0 — Controlled part removal

Scripted scenario:

```text
remove power cable
→ authoritative construct mutation
→ utility topology rebuild
→ lamp/fabricator lose power
→ unrelated room/structure identities unchanged
```

### T1B.1 — Structural failure scenario

Scripted scenario:

```text
remove/damage support
→ C9 topology change
→ C14 load recompute
→ overloaded bond/section result
→ optional split/salvage
→ runtime physics/projection update
→ proxy invalidation
→ multiplayer convergence
```

Никакой demo-only collapse logic не допускается.

### T1B.2 — Room/opening scenario

- open door;
- close door;
- remove wall/window bond;
- enclosure/space state меняется по C7 semantics;
- utility state не должен случайно менять structural truth;
- repair восстанавливает исходные item identities.

### T1B.3 — HLOD / streaming composition

Проверить один и тот же объект в режимах:

```text
FULL
SIMPLIFIED / SECTION
IMPOSTOR / DISTANT_SHELL
NONE
```

При переключениях:

- authoritative checksum не меняется;
- interactive identity не дублируется;
- child presentation не остаётся одновременно с distant shell;
- возврат в near восстанавливает актуальную revision после удалённых изменений.

### T1B.4 — Recovery / reconnect

Сценарии:

- disconnect до операции;
- disconnect после authoritative commit;
- reconnect после damage;
- reconnect после item transfer;
- reconnect во время different HLOD mode;
- rebuild presentation from empty runtime cache.

## 9. Hybrid Representation research line

Эта линия запускается параллельно после появления первого D0/D1 и **не блокирует D0**.

Причина: C24 оптимален для grid structural surfaces, но сложная художественная деталь не должна навсегда деградировать до bounds/FALLBACK representation.

Целевая схема:

```text
Representation Router
├── StructuralGreedyBackend   # текущий C22/C24 path
├── ArbitraryMeshBackend      # сложная статичная geometry
├── InstanceBatchBackend      # повторяющиеся детали / MultiMesh-like path
└── InteractiveBackend        # отдельная identity/stateful presentation
```

### HRP.1 — Arbitrary static mesh compiler

Исследовать Merging Meshes-подобный алгоритм как reference, но реализовать собственный data-oriented backend:

```text
mesh_resource_id + transform + material family
→ transformed geometry batches
→ one/few ArrayMesh surfaces
```

Backend не должен принимать authoritative `Node3D` как источник истины.

### HRP.2 — Instance batching

Для повторяющихся static/cosmetic parts:

```text
one mesh + N transforms
→ bounded instance batch
```

Identity gameplay-part при необходимости хранится отдельно от draw representation.

### HRP.3 — Asset qualification

Для выбранного Sci-Fi asset pack проверить:

- scale/pivot/grid compatibility;
- material families;
- collision quality;
- source mesh complexity;
- animated vs static classification;
- batching eligibility;
- near/mid/far representation;
- отсутствие зависимости domain от scene names.

## 10. Обязательные acceptance сценарии

### Scenario A — Item inside construct

```text
A opens storage
A moves stack backpack → storage
B observes same revision
A reconnects
state is identical
```

### Scenario B — Utility dependency

```text
remove cable
→ lamp OFF
→ fabricator OFF/BLOCKED
→ building identity SAME
→ room identity SAME
→ unrelated structure SAME
```

### Scenario C — Structural damage

```text
damage support
→ structural recompute
→ deterministic damage/split result
→ both clients converge
→ repair restores original item identities
```

### Scenario D — HLOD round trip

```text
near FULL
→ travel far
→ DISTANT_SHELL
→ mutate construct authoritatively
→ return near
→ FULL rebuilt from latest revision
```

### Scenario E — Runtime purge

```text
delete all presentation/runtime nodes
→ rebuild
→ same source checksum
→ same semantic states
```

## 11. Network validation profile

Минимум для T1 candidate:

```text
LOCAL
50 ms latency
150 ms latency
1% loss
5% loss
duplicate/reorder
disconnect/reconnect
```

На каждом профиле проверяется canonical state, а не визуальная идеальность.

Блокеры:

```text
item loss
duplication
double commit
divergent construct revision
wrong ownership
durable state loss
reconnect identity conflict
operation depending on packet arrival order
```

Warnings, не блокирующие lab:

```text
remote jitter
slow UI confirmation
HLOD pop
asset LOD debt
shader/material polish
draw-call tuning debt
```

## 12. Метрики

Собирать отдельно:

### Domain

- part count;
- bond count;
- active capabilities;
- utility graph nodes/edges;
- structural graph nodes/edges;
- item operations/sec;
- construct operations/sec;
- revision/checksum convergence.

### Runtime

- SceneTree node count;
- active MeshInstance/Collision counts;
- proxy artifact count;
- ArrayMesh resource count;
- draw-call proxy metrics where available;
- compile/rebuild duration;
- dirty-section rebuild count;
- cache hit/miss/eviction;
- estimated GPU bytes.

### Network

- bytes/packets by channel;
- construct/item operation latency;
- snapshot age;
- pending operations;
- reconnect convergence duration;
- number of child identities transmitted per HLOD tier.

## 13. Структура файлов, к которой следует стремиться

Точные имена могут корректироваться при реализации, но domain boundaries должны остаться такими:

```text
scenes/labs/t1_complex_construct_demo/
    t1_complex_construct_demo.tscn

scripts/labs/t1_complex_construct_demo/
    t1_outpost_fixture_builder.gd
    t1_demo_controller.gd
    t1_demo_inspector.gd

scripts/construction/presentation/
    part_visual_profile.gd
    part_visual_catalog.gd
    construction_representation_router.gd

resources/labs/t1_complex_construct_demo/
    visual_profiles/
    definitions/

config/labs/
    t1-complex-construct-demo.v1.json

tests/labs/
    test_t1_complex_construct_contracts.gd
    test_t1_complex_construct_integration.gd
    test_t1_complex_construct_multiplayer.gd
    test_t1_complex_construct_recovery.gd
    test_t1_complex_construct_hlod.gd
```

Не создавать новые production namespaces только ради demo, если соответствующий contract уже существует в C1–C24.

## 14. Порядок реализации

```text
T1A.0 baseline/fixtures
  ↓
T1A.1 visual profile boundary
  ↓
T1A.2 D0 deterministic outpost
  ↓
T1A.3 item integration
  ↓
T1A.4 utilities/machines
  ↓
T1A.5 two-client experimental multiplayer
  ↓
T1A.6 inspector/telemetry
  ↓
D0/D1 REVIEW
  ↓
T1B.0 controlled removal
  ↓
T1B.1 structural failure
  ↓
T1B.2 rooms/openings
  ↓
T1B.3 HLOD round-trip
  ↓
T1B.4 reconnect/recovery
  ↓
T1 ACCEPTANCE CANDIDATE
  ↓ requires formal T0 ACCEPTED
T1 ACCEPTED
  ↓
T2 D2/D3 SCALE
```

Hybrid Representation `HRP.1–HRP.3` разрешено вести параллельно после D0, но он не должен задерживать доказательство core composition.

## 15. Definition of Done для T1

T1 готов к acceptance, когда одновременно доказано:

```text
[PASS] T0 formally accepted
[PASS] one nontrivial complex outpost exists as authoritative construction
[PASS] real Item interactions work inside it
[PASS] doors/openings/rooms use existing semantic paths
[PASS] utilities affect machines/capabilities through existing C15 path
[PASS] damage/removal uses existing C9/C14 path
[PASS] repair preserves original item identities
[PASS] two clients converge after each mutation
[PASS] reconnect restores canonical state
[PASS] offline path uses the same domain rules
[PASS] HLOD transitions do not change authoritative state
[PASS] runtime projection can be destroyed/rebuilt
[PASS] no presentation object becomes canonical authority
```

После этого T2 занимается масштабом и performance, а не исправлением фундаментальной композиции.

## 16. Что не входит в T1

Не блокируют T1:

- финальный art direction;
- полноценная атмосфера/планета;
- NX7–NX9 completion;
- глобальный server handoff;
- 100k production base;
- полноценная economy loop;
- AI combat;
- final weapon system;
- perfect interpolation/prediction feel;
- baked impostor texture pipeline;
- final arbitrary mesh decimation.

## 17. Следующий переход

После `T1 ACCEPTED`:

```text
T2 Construction Scale
├── D2 1k–2k real complex object
├── D3 10k+ real base
├── optional 100k stress
├── Hybrid Representation hardening
├── section dirty rebuild performance
└── network interest/HLOD tuning
```

После T2 Construction и T4 Matter сходятся в T5 Matter + Construction Composition.
