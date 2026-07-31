# Mutable Worlds Roadmap — изменяемая порода, астероиды, пещеры и добыча

**Base checkpoint:** `v16.10.6-architecture-a3-single-server-multiplayer`.
**Тип документа:** implementation roadmap, без изменения production runtime.
**Архитектура:** `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md`.
**Решение:** `docs/architecture/adr/ADR-017-dynamic-matter-fabric.md`.

## 1. Назначение карты

Карта делит развитие на три независимых потока:

```text
LAB — отдельная лаборатория астероида
    доказывает домен вещества без риска для текущей Луны

MOON — постепенная интеграция в наиболее детальные лунные регионы
    сохраняет GLOBAL/REGIONAL поверхность и заменяет только локальную истину

PRODUCTION — network, distributed compute, performance и multi-body lifecycle
    подключается после доказанной локальной семантики
```

Основное правило последовательности:

> До завершения лабораторных gates рабочие `moon`, `earth` и `earth_moon` не меняют канонический генератор, collision или persistence.

Лабораторный поток можно вести параллельно B1/B2 как изолированную simulation feature branch, если он не меняет frozen gameplay/network contracts. Production matter networking начинается только в согласованном roadmap checkpoint.

## 2. Результат ревизии текущего проекта

### Сильные основания, которые нужно использовать

- `MoonWorld` уже является façade над конкретным terrain provider.
- `config/worlds/catalog.json` поддерживает отдельные лаборатории.
- body-fixed frames и double precision уже приняты.
- `CubeSphereGrid` стабильно адресует внешнюю поверхность.
- S0 предоставляет generic hierarchical 3D cells и shards.
- A1 поддерживает non-item aggregates.
- M0 поддерживает атомарные multi-aggregate transactions.
- S1 отделяет compute worker от authority.
- M1–M6 дают единый command/replica/persistence path.
- async terrain streaming уже умеет data-only background build и main-thread commit.

### Ограничения, которые нельзя игнорировать

- текущая Луна является radial heightfield;
- `procedural_moon_terrain.gd` объединяет generator, mesh, collision, streaming и presentation;
- near-detail частично зависит от активного `surface_center_direction`;
- local crater catalogs создаются на регион, а не являются глобальным persistent feature catalog;
- cube-sphere partition не адресует глубину;
- существующий persistence хранит entities, но не канонические matter bricks;
- current `get_altitude()` предполагает одну внешнюю поверхность вдоль радиуса;
- текущая лунная физика не умеет detached body fragments.

## 3. Целевой изолированный мир

Первый эксперимент создаётся как отдельный world runtime:

```text
world_id: asteroid_matter_lab
display_name: Лаборатория изменяемого астероида
instance_id: scenario-asteroid-matter-lab
body_id: asteroid-lab-001
body_radius_m: 1000.0
body_seed: 2026073101
body_generator_id: asteroid-matter-v1
body_generator_version: 1
frame_id: body/asteroid-lab-001/fixed
space_id: asteroid-lab-001
grid_id: body-cartesian-octree
grid_revision: 1
root_half_extent_m: 1024.0
mean_density_kg_m3: 2400.0
```

Первая сцена должна содержать:

- spectator и jetpack controller;
- asteroid presentation root;
- matter debug overlay;
- бур с фиксированными тестовыми параметрами;
- material receiver/container;
- консольные команды лаборатории;
- automated acceptance scenarios.

Астероид не добавляется в `config/planets/celestial_system.json` на первых этапах. Его body-fixed frame принадлежит isolated runtime.

## 4. Общая карта этапов

```text
MW0  Matter contracts and invariants
 ↓
MW1  Fixed-seed procedural asteroid sampler
 ↓
MW2  3D cells, sparse bricks and query service
 ↓
MW3  Local mesh, collision and streaming laboratory
 ↓
MW4  Excavation, deposition and Item Graph mass transfer
 ↓
MW5  Matter persistence, journal and compaction
 ↓
MW6  Connectivity, fragmentation and terminal destruction
 ↓
MW7  Geology, mineral deposits and survey
 ↓
MW8  Cave graph, loose matter and collapse prototype
 ───────────────── isolated laboratory gate ─────────────────
MI0  Canonical Moon geology sampler and A/B parity
 ↓
MI1  Local matter overlay bubble on the Moon
 ↓
MI2  Lunar caves, deposits and deep mining
 ↓
MI3  Construction, supports, loose regolith and navigation
 ↓
MI4  Persistent regional streaming and far-surface summaries
 ───────────────── Moon integration gate ────────────────────
MP0  Canonical network commands and replica projection
 ↓
MP1  Matter authority shards and cross-cell operations
 ↓
MP2  Distributed compute and bulk brick delivery
 ↓
MP3  Dynamic small bodies in celestial space
 ↓
MP4  Performance hardening and production acceptance
```

Каждый этап закрывается отдельной короткоживущей веткой, focused runner, regression и checkpoint documentation.

---

# Поток LAB — изолированный астероид

## MW0 — Matter contracts and invariants

### Цель

Создать чистый domain foundation без Node, Mesh и SceneTree.

### Рекомендуемая ветка

```text
feature/mw0-matter-contracts
```

### Рекомендуемый checkpoint

```text
v17.0.0-simulation-mw0-matter-contracts
```

**MW0 принят 2026-07-31, delivery `fix1`.** Focused-профиль прошёл `2011/2011`, A3 и M6 regression остались PASS. Контракты считаются базой geological track; несовместимые изменения требуют отдельной версии.

Фактический version number следует подтвердить при старте ветки с актуального `main`; логический ID `MW0` менять нельзя.

### Добавить

```text
scripts/simulation/matter/contracts/matter_material_definition.gd
scripts/simulation/matter/contracts/matter_composition.gd
scripts/simulation/matter/contracts/matter_sample.gd
scripts/simulation/matter/contracts/matter_body_definition.gd
scripts/simulation/matter/contracts/matter_brick_address.gd
scripts/simulation/matter/contracts/matter_brick_snapshot.gd
scripts/simulation/matter/contracts/matter_mutation_request.gd
scripts/simulation/matter/contracts/matter_mutation_result.gd
scripts/simulation/matter/contracts/matter_mass_ledger.gd
scripts/simulation/matter/matter_contract_utils.gd
```

### Решения этапа

1. Все payload JSON-safe и exact-field validated.
2. `MatterBrickAddress` ссылается на `SimulationCellAddress`; не копирует universe/instance/frame identity произвольно.
3. `MatterSample` не содержит presentation material.
4. Composition использует stable material IDs и нормализованные mass fractions.
5. `MatterMassLedger` проверяет замкнутость баланса.
6. Geometry sample и composition sample могут иметь разные storage channels.
7. Quantity units явно входят в имена полей.

### Минимальный каталог материалов

```text
matter/regolith-loose
matter/regolith-compacted
matter/basalt
matter/fractured-basalt
matter/water-ice
matter/iron-nickel-ore
matter/silicate-waste
```

### Тесты

- exact schema fields;
- invalid IDs;
- NaN/INF rejection;
- negative density rejection;
- fractions sum validation;
- deterministic canonical JSON;
- roundtrip;
- checksum mutation detection;
- mass ledger positive and negative scenarios;
- presentation object rejection;
- fuzz/property tests для compositions и ledgers.

### Gate

```text
Matter contracts validate without SceneTree.
100% negative contract cases pass.
No existing runtime file is modified.
```

---

## MW1 — Fixed-seed procedural asteroid sampler

### Цель

Доказать, что километровый астероид существует как детерминированное объёмное поле без полного voxel allocation.

**Implementation candidate подготовлен 2026-07-31:** `v17.1.0-simulation-mw1-fixed-seed-asteroid`. Реализованы stable feature catalog, observer-independent sampler, closed outer-surface query, natural void, ore/ice geology, 128-point golden fixture и deterministic mass integration. Этап не меняет production worlds и до независимого Godot-прогона остаётся `CANDIDATE`.

### Ветка

```text
feature/mw1-fixed-seed-asteroid
```

### Добавить

```text
config/matter/mw1-fixed-seed-asteroid.v1.json
scripts/simulation/matter/generation/deterministic_field_3d.gd
scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd
scripts/simulation/matter/generation/asteroid_feature_catalog.gd
scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd
scripts/simulation/matter/contracts/matter_body_mass_estimate.gd
scripts/simulation/matter/analysis/matter_body_mass_integrator.gd
tests/matter/generation/test_mw1_fixed_seed_asteroid.gd
```

### Базовый генератор

```text
reference ellipsoid
+ low-frequency body deformation
+ deterministic embedded lobes
- impact depressions
- natural void features
+ geological material features
```

Не использовать один шум как финальную форму. Все крупные features должны иметь stable IDs, чтобы их можно было диагностировать и мигрировать.

### Обязательные свойства

- центр тела заполнен;
- вне root bounds вещества нет;
- поверхность замкнута;
- одинаковый seed создаёт идентичные samples;
- sample не зависит от порядка запросов;
- material composition детерминирован;
- approximate volume/mass convergence измеряется на нескольких resolutions;
- generator version входит в snapshot identity.

### Тестовые контрольные точки

Зафиксировать не менее 128 body-fixed coordinates:

- центр;
- оси ±X/±Y/±Z;
- точки возле поверхности;
- точки в железо-никелевой линзе;
- точки в ледяном кармане;
- точки в естественной полости;
- точки вне тела.

Golden fixture хранит canonical hash, а не platform-specific floating text dump.

### Gate

```text
Same seed/version → same sample hashes.
Different seed → different feature catalog hash.
Mass estimate stable within declared tolerance.
No mesh or collision code exists yet.
```

---

## MW2 — 3D cells, sparse bricks and query service

### Цель

Материализовать только нужные области и получить стабильную 3D spatial identity.

### Ветка

```text
feature/mw2-sparse-matter-storage
```

### Grid первой версии

```text
grid_id: body-cartesian-octree
grid_revision: 1
root bounds: 2048 × 2048 × 2048 m
child capacity: 8
brick cells per axis: 16
standard edit spacing: 1.0 m
precision edit spacing: 0.25 m, зарезервировано, не требуется для gate
coarse topology spacing: 8.0 m
```

Полный астероид не разворачивается в standard bricks. Brick создаётся, когда:

- попадает в active query/mesh window;
- пересечён mutation;
- содержит persistent deviation;
- нужен precise collision;
- требуется refinement connectivity.

### Добавить

```text
scripts/simulation/matter/spatial/body_cartesian_octree_resolver.gd
scripts/simulation/matter/storage/matter_repository_port.gd
scripts/simulation/matter/storage/in_memory_sparse_matter_store.gd
scripts/simulation/matter/queries/matter_query_service.gd
scripts/simulation/matter/queries/matter_raycast_result.gd
```

### Query API

```text
sample_matter(body_id, body_fixed_position)
query_brick(address)
raycast_matter(origin, direction, max_distance)
find_nearest_surface(position, max_distance)
query_material_column(origin, direction, max_distance, step_policy)
```

Query resolution выбирается явно. Gameplay не должен случайно получать render LOD sample.

### Boundary rules

- shared samples соседних bricks вычисляются из одного canonical coordinate;
- ghost borders не являются отдельным persistent state;
- lower-resolution parent summary не перезаписывает child edits;
- empty procedural cells не сохраняются;
- stored brick обязан ссылаться на exact base generator version.

### Тесты

- address parent/child;
- bounds containment;
- neighbour face consistency;
- same point through two adjacent bricks;
- sparse allocation count;
- query fallback to procedural base;
- stored override precedence;
- invalid mixed generator version;
- deterministic raycast;
- unload/reload without data loss.

### Gate

```text
A tunnel-shaped synthetic mutation can cross multiple bricks in memory.
Queries see one continuous result across every brick boundary.
Untouched asteroid still allocates no full-volume brick set.
```

---

## MW3 — Local mesh, collision and streaming laboratory

### Цель

Создать отдельный playable/debug world с локальным SDF mesh и collision.

### Ветка

```text
feature/mw3-asteroid-matter-lab
```

### Добавить world

```text
config/worlds/catalog.json                 modified
scripts/app/asteroid_matter_lab_app.gd
scenes/testing/asteroid_matter_lab.tscn
scripts/world/matter/matter_mesh_adapter.gd
scripts/world/matter/matter_collision_adapter.gd
scripts/world/matter/matter_streaming_manager.gd
scripts/world/matter/matter_debug_renderer.gd
config/matter/asteroid_matter_lab.v1.json
```

### Заимствовать из текущего terrain streaming

Можно повторно использовать паттерны:

- immutable request data;
- off-tree worker sampler;
- `WorkerThreadPool`;
- latest-wins request fencing;
- staged main-thread creation;
- old representation active until new ready;
- tiled collision commit;
- drain on world unload;
- performance JSONL.

Нельзя вызывать текущий `TerrainStreamingManager` напрямую: его contracts radial-surface-specific. Нужен отдельный manager с общими низкоуровневыми helpers только после появления реального повторения.

### Mesher

Первая версия:

- один выбранный CPU mesher;
- deterministic cell traversal;
- normal generation из SDF gradient или mesh topology;
- material palette per surface vertex/triangle;
- seam tests;
- collision decimation отдельно от visual mesh.

Конкретный алгоритм фиксируется внутри checkpoint после prototype comparison. Domain contracts не должны зависеть от Marching Cubes, Surface Nets, Dual Contouring или Transvoxel.

### Лабораторные команды

```text
matter.debug.toggle
matter.debug.mode sdf|material|brick|revision|connectivity
matter.teleport.surface <x> <y> <z>
matter.sample <x> <y> <z>
matter.mesh.rebuild
matter.cache.report
matter.performance.save
```

### Performance budgets первого gate

Целевые, не production-финальные:

```text
active visual radius: 128 m
active collision radius: 64 m
standard sample spacing: 1 m
main-thread commit budget: ≤ 4 ms per frame
no frame > 100 ms during normal streamed activation after warm-up
world unload drain: ≤ 30 s hard timeout, fail-closed
```

### Тесты

- lab boot;
- isolated world commands;
- no hidden Moon/Earth runtime;
- worker produces data-only payload;
- stale request rejection;
- world switch during generation;
- collision creation and removal;
- mesh seam screenshot/geometry test;
- cache and drain;
- no canonical state mutation from presentation rebuild.

### Gate

```text
world.load asteroid_matter_lab
→ spectator flies around a 1000 m radius body
→ local surface streams without changing moon/earth runtimes
→ collision and mesh originate from Matter Query Service
```

---

## MW4 — Excavation, deposition and Item Graph mass transfer

### Цель

Сделать бурение authoritative domain operation с сохранением вещества.

### Ветка

```text
feature/mw4-matter-mutations
```

### Operation model

Инструмент отправляет swept shape:

```text
previous tool transform
current tool transform
tool shape
operation mode
energy budget
destination container
expected matter revisions
```

Не отправлять список frame-based sphere stamps.

### Mutation types v1

```text
EXCAVATE
DEPOSIT_LOOSE
COMPACT
```

`FRACTURE`, `MELT`, `VAPORIZE` остаются следующими versions.

### Aggregate model

Минимум:

```text
MatterBodyAggregate
MatterShardAggregate
MaterialBatchItem
ContainerAggregate
```

Одна excavation transaction:

1. проверяет authority и expected revisions;
2. вычисляет swept volume;
3. определяет удалённый composition;
4. проверяет tool energy и receiver capacity;
5. обновляет affected matter shards;
6. создаёт или увеличивает Material Batch Item;
7. обновляет container relation;
8. фиксирует mass ledger и outbox;
9. возвращает stable replay result.

### Material batch

```text
item definition: item/material-batch
state:
    total_mass_kg
    bulk_volume_m3
    composition
    temperature_k
    source_body_id
    source_operation_id
```

### Тесты

- one-brick dig;
- cross-brick swept dig;
- high-speed tool crossing;
- exact replay;
- same operation ID with different fingerprint;
- stale revision;
- insufficient energy;
- full container;
- partial acceptance policy;
- mass conservation;
- material composition conservation;
- failed commit leaves all aggregates unchanged;
- presentation lag does not affect result.

### Playable gate

```text
Игрок/тестовый бур проходит сквозь поверхность.
Возникает реальный тоннель.
Извлечённая масса появляется в контейнере.
После выброса batch можно вернуть как loose matter.
```

---

## MW5 — Matter persistence, journal and compaction

### Цель

Тоннели, добыча и разрушение переживают restart без сохранения generated mesh.

### Ветка

```text
feature/mw5-matter-persistence
```

### Storage model

```text
procedural base definition
+ recent mutation journal
+ compacted matter brick snapshots
+ body/shard summaries
+ operation replay records
```

### Repository boundary

```text
MatterRepositoryPort
    load_body_manifest
    load_brick
    save_atomic_transaction
    list_dirty_bricks
    compact_brick
    verify_content_hash
```

Не добавлять прямые `FileAccess` calls в sampler, mutation service или presentation.

### Compaction

Compaction заменяет диапазон terminal operations одним brick snapshot:

```text
base generator hash
from operation sequence
to operation sequence
brick revision
content hash
material totals
boundary summary
```

После compaction exact replay terminal results остаются доступны через bounded replay records согласно общей persistence policy.

### Тесты

- save/load after one tunnel;
- save/load after cross-brick dig;
- compaction equivalence;
- crash after prepare;
- crash after commit;
- exact replay after restart;
- corrupt snapshot detection;
- wrong generator version rejection;
- terminal deleted body does not respawn;
- generated mesh absent from persistence.

### Gate

```text
Пробурить тоннель → завершить процесс → запустить снова
→ форма, масса, container contents и operation replay совпадают.
```

---

## MW6 — Connectivity, fragmentation and terminal destruction

### Цель

Позволить астероиду расколоться и полностью исчезнуть как исходное тело.

### Ветка

```text
feature/mw6-asteroid-fragmentation
```

### Двухуровневая связность

#### Coarse global graph

Для всего small body хранится дешёвая occupancy/connectivity summary с spacing 8 м или крупнее. Она определяет потенциальное разделение.

#### Refined local graph

Вокруг изменённой перемычки создаётся точная connectivity область на storage LOD. Полный fine scan астероида после каждого drill tick запрещён.

### Brick boundary summary

Каждый brick публикует:

```text
local component count
occupied boundary masks
component-to-boundary mapping
bonded mass
center-of-mass contribution
material totals
summary revision
```

### Fragment classification

```text
primary connected component
    сохраняет исходный body_id, если превышает policy threshold

large detached component
    новый MatterBodyAggregate

medium component
    RigidMatterFragmentAggregate

small components
    DebrisParcelAggregate

micro components
    LooseMatterBatch / dust summary
```

### Физическое состояние потомков

Для каждого потомка:

- local origin at center of mass;
- body-fixed-to-parent transform;
- mass;
- inertia tensor;
- linear velocity from original rigid motion plus impulse;
- angular velocity;
- matter shards;
- source body lineage;
- authority state.

### Terminal destruction

Исходный body завершается только через atomic transaction, которая назначает всю остаточную массу.

### Тесты

- straight tunnel does not split body;
- ring cut detaches core;
- plane cut creates two bodies;
- small chip creates fragment, not full body;
- velocities conserve declared momentum tolerance;
- total mass conserved;
- save/load after split;
- replay does not duplicate descendants;
- full extraction creates terminal body state;
- late command against terminal body rejected.

### Gate

```text
Игрок делает разрез.
Астероид становится двумя независимыми физическими телами.
Одно тело затем полностью перерабатывается.
Исходная масса и lineage сходятся после restart.
```

---

## MW7 — Geology, mineral deposits and survey

### Цель

Перейти от однородной породы к осмысленной добыче.

### Ветка

```text
feature/mw7-geology-and-deposits
```

### Geological features v1

```text
layer
vein
lens
intrusion
fracture-zone
porous-zone
ice-pocket
embedded-boulder
```

### Properties, влияющие на gameplay

- bulk density;
- hardness;
- compressive strength;
- tensile strength;
- fracture toughness;
- abrasiveness;
- cohesion;
- porosity;
- volatile fraction;
- processing yield.

### Tool interaction

```text
required power = function(material hardness, removed volume, tool profile)
wear = function(abrasiveness, contact distance, tool material)
yield = function(composition, tool selectivity, receiver efficiency)
```

Первые коэффициенты могут быть упрощёнными, но units и conservation должны быть явными.

### Survey API

```text
MatterSurveyRequest
    sensor_type
    origin
    direction
    range_m
    resolution_m
    energy_budget

MatterSurveyResult
    anomaly samples
    material probability
    estimated depth
    confidence
    source revision
```

Сенсор не возвращает точный hidden world snapshot, если gameplay design этого не разрешает.

### Тесты

- deterministic deposit;
- grade continuity across bricks;
- depletion after mining;
- scan sees revision changes;
- tool energy differs by material;
- refining output mass balance;
- hidden exact data not leaked by low-resolution sensor.

### Gate

```text
Найти железо-никелевую линзу сканером.
Пробурить к ней тоннель.
Получить mixed ore batch.
Переработать batch в products и waste без создания массы.
```

---

## MW8 — Cave graph, loose matter and collapse prototype

### Цель

Доказать процедурные внутренние пространства и минимальную механику устойчивости до переноса на Луну.

### Ветка

```text
feature/mw8-caves-and-loose-matter
```

### Cave generation

```text
CaveGraph
├── entrance
├── corridor spline
├── chamber
├── vertical shaft
├── sealed branch
└── weak roof zone
```

Graph создаётся до geometry. Acceptance проверяет связность графа, минимальный clearance и bounds.

### Loose matter v1

Состояния:

```text
BONDED
FRACTURED
RIGID_FRAGMENT
LOOSE_PARCEL
SETTLED_FIELD
CONTAINED
COMPACTED
```

Первая физика не обязана быть MPM. Допустим event-driven local collapse solver:

1. mutation меняет support graph;
2. stability evaluator помечает unstable region;
3. region превращается в несколько fragments и loose parcel;
4. local gravity/ballistic solver двигает их;
5. после успокоения они сворачиваются в settled field.

### Тесты

- cave graph reproducibility;
- entrance reaches chamber;
- no sub-threshold isolated voids;
- weak roof collapses after support removal;
- strong roof remains;
- support construct prevents collapse;
- low gravity produces ballistic debris;
- settled conversion preserves mass;
- save/load during active and settled states.

### Isolated laboratory acceptance gate

После MW8 лаборатория должна независимо доказывать:

```text
procedural body
+ natural cave
+ heterogeneous geology
+ survey
+ drilling
+ material transfer
+ persistence
+ fragmentation
+ full destruction
+ loose matter prototype
```

Только после этого разрешён production-impacting Moon integration.

---

# Поток MOON — интеграция с текущей поверхностью

## MI0 — Canonical Moon geology sampler and A/B parity

### Цель

Создать стабильный procedural source, не меняя текущую картинку и gameplay.

### Ветка

```text
feature/mi0-canonical-moon-geology
```

### Выделить

```text
scripts/simulation/matter/generation/moon_geology_sampler.gd
scripts/simulation/matter/generation/moon_surface_feature_catalog.gd
scripts/world/matter/legacy_moon_surface_adapter.gd
```

### Главное изменение

Observer-dependent microdetail перестаёт участвовать в canonical sample. Он остаётся декоративным слоем presentation до следующей миграции.

Cell-local craters получают stable feature IDs, полученные из canonical cube-sphere/cell identity, а не из текущего center window.

### Parity harness

Сравнить старый и новый providers:

- глобальные контрольные directions;
- текущие spawn regions;
- crater centers;
- LOCAL mesh bounds;
- surface normal;
- player spawn clearance;
- atmosphere surface height;
- screenshots.

Нулевая визуальная разница не обязательна. Обязательны:

- стабильность нового sampler;
- ограниченная и измеренная разница;
- отсутствие mutation/persistence change;
- сохранение boot/regression.

### Gate

```text
Moon uses the new canonical sampler through compatibility adapter.
No volumetric edit is enabled.
All current world/network/item tests remain green.
```

---

## MI1 — Local matter overlay bubble

### Цель

В одном фиксированном лунном испытательном регионе заменить центральную часть LOCAL surface на volumetric matter.

### Ветка

```text
feature/mi1-lunar-matter-overlay
```

### Тестовый регион

Следует зафиксировать canonical cube-sphere address после выбора существующей детальной локации. До фиксации адреса запрещено использовать camera-relative coordinates в persistence.

### Geometry stack

```text
GLOBAL Moon mesh                  unchanged
REGIONAL cap                      unchanged
outer LOCAL annulus               legacy/canonical radial mesh
central matter bubble             volumetric mesh and collision
underground                       volumetric only
```

### Seam contract

На boundary bubble:

- base SDF точно совпадает с canonical radial surface;
- persistent edits fade не применяют: изменение либо существует, либо нет;
- только presentation normal/material detail может blend;
- old collision удаляется внутри overlap mask;
- surface query выбирает matter result внутри activation region.

### Gate

```text
Игрок перемещается через seam без ступени и двойной коллизии.
Можно сделать одну persistent яму и короткий тоннель.
При выключенном feature flag текущая поверхность работает как раньше.
```

---

## MI2 — Lunar caves, deposits and deep mining

### Цель

Добавить generated spaces и полезные ископаемые на глубине.

### Ветка

```text
feature/mi2-lunar-caves-and-mining
```

### Cave roots

Cave graph привязывается к canonical volumetric region identity. Surface entrance может быть отдельным feature, связанным с cave system ID.

### Geological profile v1

```text
surface loose regolith
compacted regolith
fractured impact layer
competent basalt
fault zones
water-ice pockets
iron/titanium-bearing deposits
```

### Vertical acceptance

```text
surface scan
→ approximate anomaly
→ drill shaft
→ intersect generated cave
→ reach deposit
→ extract mixed material
→ return batch to container
→ save/restart
```

### Gate

- cave remains identical by seed/version;
- player edits remain over generator;
- deposit does not respawn;
- tunnel crosses multiple depth cells;
- radial `get_altitude()` is not used for underground collision/gameplay.

---

## MI3 — Construction, supports, loose regolith and navigation

### Цель

Связать matter domain с будущей стройкой и роботами.

### Ветка

```text
feature/mi3-underground-construction
```

### Terrain attachments

Конструкция не запекается в terrain. Создаётся relation:

```text
ConstructAggregate
↔ TerrainAnchorRelation
↔ Matter Shard revision
```

Anchor хранит body-fixed transform, contact/support area и expected matter revision.

### Support graph

Опоры влияют на stability evaluator, но остаются Item/Construct aggregates. Удаление опоры и обвал должны быть одной причинно согласованной transaction sequence.

### Navigation

Не строить один глобальный NavMesh. Производные query fields:

```text
clearance
slope
support
roughness
material strength
wheel traction
traversability
```

Профили:

- humanoid;
- wheeled rover;
- tracked rover;
- flying drone;
- tunnelling robot.

### Gate

```text
Ровер получает маршрут по выкопанному тоннелю.
После обвала маршрут инвалидируется.
Установленная опора сохраняет проход.
```

---

## MI4 — Persistent regional streaming and far-surface summaries

### Цель

Сделать matter regions обычной частью лунного streaming lifecycle.

### Ветка

```text
feature/mi4-lunar-matter-streaming
```

### Activation sets

```text
AuthoritySet   — owned matter shards
InterestSet    — requested cells for players/robots/sensors
ActivationSet  — cells with mesh/collision/active physics
PersistenceSet — dirty or causally retained cells
```

### Surface summaries

Крупный карьер или кратер обновляет parent summary:

```text
outer surface min/max displacement
void volume
material totals
activity
content hash
summary revision
```

Дальний mesh может учитывать крупное изменение. Маленький тоннель не обязан быть видим из космоса.

### Cache rules

- generated base cache disposable;
- compacted edited brick cache persistent;
- mesh cache disposable;
- collision cache disposable;
- causal data cannot be evicted without repository commit;
- pinned bases and active caves participate in interest, но не меняют authority.

### Gate

```text
Перейти между двумя удалёнными шахтами.
Вернуться без потери edits.
Streaming не требует полного body scan.
Memory and disk budgets recorded.
```

---

# Поток PRODUCTION — сеть, распределение и физические тела

## MP0 — Canonical matter commands and replica projection

### Цель

Подключить matter gameplay к единственному `NetworkedGameplayService` path.

### Ветка

```text
feature/mp0-networked-matter-gameplay
```

### Commands

```text
MATTER_EXCAVATE_COMMAND
MATTER_DEPOSIT_COMMAND
MATTER_COMPACT_COMMAND
MATTER_SURVEY_COMMAND
```

Graphical client отправляет intent и показывает prediction-only tool feedback. Canonical matter mutates only on authority.

### Replica data

Передавать адаптивно:

- operation delta для малых изменений;
- compressed brick delta;
- complete compacted brick snapshot;
- content hashes;
- body/shard summary.

Generated untouched area воспроизводится по seed/version.

### Gate

- LOOPBACK/ENet canonical equivalence;
- two-client same-brick contention;
- reconnect receives missing state once;
- replay does not mine twice;
- Item Graph and matter mass converge on all replicas.

---

## MP1 — Matter authority shards and cross-cell operations

### Цель

Разместить volumetric state в S0 shards без смешивания identity и authority.

### Ветка

```text
feature/mp1-matter-authority-shards
```

### Boundary operation

Swept drill может затронуть несколько shards. Coordinator:

1. resolves affected cells/shards;
2. verifies one authority owner or starts approved coordination path;
3. fences epochs/revisions;
4. stages all matter/item effects;
5. commits atomically within supported authority boundary;
6. rejects unsupported cross-authority operation fail-closed.

До появления production distributed transaction protocol cross-authority mutation либо маршрутизируется одному владельцу по заранее установленной boundary policy, либо отклоняется. Нельзя имитировать атомарность несколькими независимыми commits.

### Gate

- operation across local shard boundary;
- stale boundary summary;
- owner change requires epoch increase;
- no duplicate material at boundary;
- handoff does not lose dirty bricks.

---

## MP2 — Distributed compute and bulk brick delivery

### Цель

Вынести тяжёлые pure computations без передачи authority.

### Ветка

```text
feature/mp2-distributed-matter-compute
```

### Jobs

```text
MESH_BUILD
COLLISION_BUILD
BRICK_COMPACTION
CONNECTIVITY_REFINEMENT
COLLAPSE_EVALUATION
FAR_SUMMARY_BUILD
```

Каждый proposal содержит input revision/hash. Authority отвергает stale result.

Bulk port используется для крупных snapshots; broker-specific IDs не входят в canonical matter state.

### Gate

- worker crash/retry;
- duplicate job result;
- stale input hash;
- wrong package hash;
- authority restart during job;
- local and remote compute equivalence.

---

## MP3 — Dynamic small bodies in celestial space

### Цель

Перенести доказанный астероид из isolated runtime в общий celestial/frame graph.

### Ветка

```text
feature/mp3-dynamic-small-bodies
```

### Требования

- `MatterBodyAggregate` получает inertial and fixed frames;
- orbit/trajectory state хранится отдельно от local matter geometry;
- fragmentation создаёт новые frame roots или body frame descriptors;
- body motion не переписывает body-fixed bricks;
- gravity source может использовать aggregate mass summaries;
- near-body physics promotion не меняет canonical identity.

### Gate

```text
Астероид движется в system frame.
Игрок входит в near-body frame.
Бурение меняет массу/инерцию.
Раскол создаёт два движущихся тела.
Frame transforms и persistence остаются согласованы.
```

---

## MP4 — Performance hardening and production acceptance

### Цель

Закрепить budgets, native acceleration boundaries и полную регрессию.

### Возможные native boundaries

GDScript остаётся orchestration и contracts. В native module/GDExtension могут перейти только profile-proven hotspots:

- SDF brick sampling;
- meshing;
- compression;
- connectivity;
- bulk material integration;
- granular/fragment solver.

Нельзя преждевременно переносить domain semantics в opaque native code.

### Production acceptance matrix

- fixed-seed asteroid generation;
- tunnel and cave;
- cross-brick mining;
- save/restart/replay;
- full fragmentation;
- complete destruction;
- lunar cave/deposit;
- support/collapse;
- two graphical clients;
- reconnect;
- authority epoch change;
- remote compute retry;
- world switch/drain;
- memory/disk/network budgets;
- deterministic hashes across supported platforms.

---

# 5. Что менять в текущей поверхности, а что оставить

## Оставить без замены на ранних этапах

```text
scripts/world/moon_world.gd façade
CubeSphereGrid and PartitionAddress v2
GLOBAL Moon mesh
REGIONAL cap
observer-frame render origin
current atmosphere surface-height compatibility
current world catalog lifecycle
current network gameplay path
```

## Постепенно заменить

```text
observer-dependent canonical height sampling
local collision source
central LOCAL/ULTRA surface mesh source
terrain-only gameplay raycasts
radial-only altitude assumptions underground
entity-only persistent world model for terrain edits
```

## Разделить после parity proof

```text
procedural_moon_terrain.gd
    canonical generation
    presentation meshing
    collision
    streaming
    materials
    rocks
    debug state
```

## Не делать

```text
rewrite Moon terrain before MW laboratory gates
store mesh arrays as world state
reuse cube-sphere chunk ID as a fake 3D voxel address
let UI or tool nodes mutate bricks directly
use local crater cache as persistent geology
```

# 6. Suggested project structure after MW3

```text
config/matter/
├── material_catalog.v1.json
├── asteroid_lab_body.v1.json
└── asteroid_matter_lab.v1.json

scripts/simulation/matter/
├── contracts/
├── generation/
├── spatial/
├── storage/
├── queries/
├── mutation/
├── topology/
└── validation/

scripts/world/matter/
├── matter_streaming_manager.gd
├── matter_mesh_adapter.gd
├── matter_collision_adapter.gd
├── matter_debug_renderer.gd
└── legacy_moon_surface_adapter.gd

scripts/app/
└── asteroid_matter_lab_app.gd

scenes/testing/
└── asteroid_matter_lab.tscn

tests/matter/
├── contracts/
├── generation/
├── storage/
├── mutation/
├── topology/
├── integration/
└── process/
```

# 7. Focused runners

Рекомендуемая последовательность runners:

```text
RUN_MW0_MATTER_CONTRACTS_TESTS
RUN_MW1_ASTEROID_GENERATION_TESTS
RUN_MW2_SPARSE_MATTER_TESTS
RUN_MW3_ASTEROID_LAB_TESTS
RUN_MW4_MATTER_MUTATION_TESTS
RUN_MW5_MATTER_PERSISTENCE_TESTS
RUN_MW6_ASTEROID_DESTRUCTION_TESTS
RUN_MW7_GEOLOGY_MINING_TESTS
RUN_MW8_CAVE_LOOSE_MATTER_TESTS
RUN_MI0_MOON_GEOLOGY_PARITY_TESTS
RUN_MI1_LUNAR_MATTER_OVERLAY_TESTS
RUN_MUTABLE_WORLDS_REGRESSION_TESTS
```

Имена файлов должны соответствовать существующей кроссплатформенной runner policy проекта: `.ps1` и `.sh`, когда branch действительно создаёт runners.

# 8. Обязательные property и invariant tests

Помимо scripted examples, нужны свойства:

```text
sample determinism
operation idempotency
mass conservation
revision monotonicity
shared-boundary equality
save/load equivalence
compaction equivalence
connectivity consistency
fragment lineage uniqueness
no presentation object in canonical payload
no authority rollback
no generator-version reinterpretation
```

Для floating calculations tolerance объявляется в contract и не подбирается внутри теста постфактум.

# 9. Параллельность работ

Допустимо параллельно после MW0:

```text
MW1 generator research
material catalog research
mesher prototype comparison
cave graph prototype
```

Но merge order остаётся последовательным. Prototype branches не меняют production contracts.

Нельзя параллельно менять один и тот же public boundary:

- `MatterSample`;
- `MatterBrickSnapshot`;
- `MatterMutationRequest`;
- body/grid identity;
- mass ledger semantics.

После принятия MW0 любые изменения этих contracts требуют versioned checkpoint.

# 10. Приоритет ближайшей реализации

Следующий практический этап после документации:

```text
MW0 — Matter contracts and invariants
```

Почему не начинать со сцены:

- текущий проект уже доказал ценность contract-first подхода;
- mesh prototype без stable coordinates и mass semantics быстро станет тупиковой веткой;
- A1/M0/S0 дают готовые границы, которые выгодно использовать сразу;
- asteroid lab можно подключить в MW3 без риска для Moon runtime.

Рекомендуемая первая поставка должна содержать только:

- contracts;
- material catalog;
- in-memory fixtures;
- validation/property tests;
- architecture/checkpoint docs;
- без SceneTree и без изменения current worlds.

# 11. Главные вертикальные acceptance scenarios

## A. Fixed-seed asteroid lifecycle

```text
load asteroid_matter_lab
→ verify seed/version/body hash
→ drill a tunnel through the body
→ extract material into a container
→ save/restart
→ cut a structural bridge
→ split into two bodies
→ fully process one body
→ verify terminal state and mass ledger
```

## B. Lunar deep mining

```text
load moon test region
→ survey anomaly
→ drill shaft through regolith and basalt
→ enter deterministic cave
→ mine ice/ore deposit
→ install support
→ remove support in controlled test
→ observe collapse and route invalidation
→ save/restart
```

## C. Networked matter contention

```text
server + two graphical clients
→ both target the same matter brick
→ authority commits one revision order
→ containers and matter mass converge
→ client A disconnects
→ client B continues mining
→ client A reconnects
→ receives missing brick state once
→ replay creates no second material
```

# 12. Критерий завершения всей карты

Система считается состоявшейся, когда одновременно верно:

1. астероид радиусом 1000 м существует по фиксированному seed;
2. его можно пробурить, расколоть и полностью уничтожить;
3. масса отслеживается между terrain, fragments, loose matter и Item Graph;
4. изменения переживают crash/restart и exact replay;
5. Луна сохраняет текущий дальний LOD, но локально поддерживает пещеры и шахты;
6. месторождения детерминированы и истощаются;
7. подземные gameplay queries не зависят от radial heightfield;
8. network clients являются command producers/replicas, а не matter authority;
9. workers ускоряют расчёт, но не фиксируют canonical state;
10. старые `moon`, `earth`, `earth_moon`, items и multiplayer regressions остаются рабочими.
