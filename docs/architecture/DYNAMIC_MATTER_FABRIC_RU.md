# Dynamic Matter Fabric — парадигма изменяемых миров PlanetSimulator

**Статус:** целевая архитектура; MW0 contracts implementation candidate подготовлен.
**Основание анализа:** `v16.10.6-architecture-a3-single-server-multiplayer`.
**Решение:** текущая планетарная поверхность сохраняется как совместимое дальнее и переходное представление; каноническое изменяемое состояние переносится в отдельный домен вещества.
**Связанный ADR:** `docs/architecture/adr/ADR-017-dynamic-matter-fabric.md`.
**План реализации:** `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md`.
**Первый implementation checkpoint:** `docs/architecture/MW0_MATTER_CONTRACTS_RU.md`.

## 1. Цель

PlanetSimulator должен поддерживать один непрерывный жизненный цикл вещества:

```text
геология
→ порода
→ разрушение
→ обломки / рыхлое вещество
→ добытый Material Batch
→ контейнер
→ переработка
→ компонент
→ конструкция
→ разрушение конструкции
→ возврат материала в мир
```

На этом основании должны работать два класса тел:

1. малые тела, которые разрешено полностью пробурить, расколоть и уничтожить;
2. планеты и луны, у которых изменяется локальная кора, пещеры, шахты, кратеры и насыпи, но не материализуется весь объём планеты.

Главный принцип:

> Мир логически объёмный везде, но хранит только процедурное описание и разреженные причинно значимые изменения.

Меш, коллизия, дальний heightfield и debug-визуализация не являются авторитетным состоянием.

## 2. Что уже есть в проекте

### 2.1. Иерархические системы отсчёта

Проект уже хранит положение поверхности в body-fixed frame:

```text
body/earth/fixed
body/moon/fixed
```

`SpatialRef`, `FrameGraph`, аналитическое движение тел и observer render frame уже разделяют:

- каноническую координату;
- движение небесного тела;
- серверное владение;
- локальную координату Godot возле render origin.

Домен вещества обязан использовать те же frame. Никакой matter brick не должен адресоваться относительно игрока или текущего floating origin.

### 2.2. Surface partition

Лунная и земная поверхность адресуются через `CubeSphereGrid`:

```text
body-fixed direction
→ cube face
→ zone
→ chunk
```

Это правильная сетка для:

- surface interest;
- дальнего рельефа;
- поверхностных сущностей;
- региональных сводок;
- маршрутизации запроса к телу.

Но это двумерная угловая сетка. Она не может сама выразить:

- тоннель под другим тоннелем;
- несколько поверхностей вдоль одного радиуса;
- внутреннюю полость астероида;
- отделившийся объём вещества.

Поэтому `PartitionAddress` cube-sphere сохраняется, но не становится адресом объёмного brick.

### 2.3. Универсальный пространственный фундамент S0

В проекте уже есть:

- `SimulationCellAddress` с `grid_id`, `grid_revision`, `root_id`, `level`, `path`;
- `SpatialCellDescriptor` с явным `frame_id` и трёхмерными bounds;
- `AggregateShardDescriptor`;
- neighbour topology;
- boundary summaries;
- `SpatialAggregateIndex`.

Это подходящее основание для иерархической 3D-сетки вещества. Новая система не должна создавать вторую несовместимую модель пространства.

### 2.4. Generic aggregates и транзакции

A1 позволяет регистрировать non-item aggregates. M0 уже обеспечивает:

- create/update/delete нескольких aggregates;
- owner/epoch/revision fencing;
- атомарный commit;
- stable replay по `operation_id`;
- transactional outbox;
- межагрегатные invariants.

Следовательно, добыча может быть одной транзакцией:

```text
Matter Shard теряет массу
+ Material Batch Item получает массу
+ Container Aggregate принимает Item
+ outbox публикует изменения
```

Либо не меняется ничего.

### 2.5. Distributed compute

S1 уже разделяет authority и worker. Это напрямую подходит для:

- построения mesh;
- пересчёта коллизий;
- compaction brick;
- connectivity scan;
- расчёта обвала;
- построения coarse summaries.

Worker возвращает proposal. Только authority фиксирует результат.

### 2.6. Multi-world runtime

`config/worlds/catalog.json` уже содержит изолированные лаборатории `item_lab` и `playground`. Поэтому новый `asteroid_matter_lab` должен быть отдельным world runtime и не затрагивать рабочие `moon`, `earth` и `earth_moon` до интеграционного этапа.

## 3. Текущее состояние поверхности Луны

### 3.1. Реализованная модель

`scripts/world/terrain/procedural_moon_terrain.gd` одновременно выполняет несколько обязанностей:

- процедурно вычисляет radial height;
- создаёт GLOBAL UV-сферу;
- создаёт REGIONAL/LOCAL/ULTRA radial caps;
- генерирует локальные каталоги кратеров;
- создаёт камни и материалы;
- строит collision tiles;
- управляет async streaming и recent surface cache;
- содержит presentation state и render-origin логику.

Каноническая геометрическая модель сейчас имеет вид:

```text
surface_point(direction) = direction * (moon_radius + surface_height(direction))
```

Это heightfield на сфере. Он отлично подходит для внешней поверхности, но принципиально не выражает внутренние полости и навесы.

### 3.2. Что нельзя использовать как каноническую геологию

`get_surface_height()` включает детали, зависящие от текущего локального окна:

- `_get_micro_surface_relief()` использует расстояние до `surface_center_direction`;
- локальные и микрократеры пересоздаются для активного региона;
- часть детализации предназначена для camera-local visual fidelity.

Поэтому прямое определение:

```text
base_sdf(position) = length(position) - radius - get_surface_height(direction)
```

не является стабильным persistent-контрактом. Один и тот же point может получить разную микродеталь после recenter.

Необходимо разделить:

```text
CanonicalMoonGeologySampler
    детерминированен по body_id, seed, generator_version и координате

LegacyMoonPresentationSampler
    может добавлять camera-local декоративную детализацию
```

После появления канонического sampler текущий mesh-generator постепенно переводится на него. До этого старый Moon runtime остаётся неизменным.

### 3.3. Что следует сохранить

Не требуется выбрасывать:

- body-fixed координаты;
- cube-sphere zones/chunks;
- GLOBAL/REGIONAL дальние меши;
- observer-frame floating origin;
- async data-only generation pattern;
- staged main-thread mesh/collision commit;
- recent surface cache;
- `MoonWorld` façade;
- текущие UI и atmosphere surface queries для внешней поверхности.

Нужно заменить только источник локальной истины и разделить монолит на порты.

## 4. Целевая модель состояния

Для точки `p` в body-fixed frame:

```text
MatterState(p, tick) =
    BaseBodyField(p)
  + GeologicalFeatures(p)
  - ProceduralVoidFeatures(p)
  + PersistentMatterMutations(p)
  + ActiveMatterState(p, tick)
```

Где:

- `BaseBodyField` задаёт базовую форму тела;
- `GeologicalFeatures` задаёт слои, жилы, включения, разломы и свойства;
- `ProceduralVoidFeatures` задаёт пещеры и естественные пустоты;
- `PersistentMatterMutations` хранит бурение, взрывы, засыпание и уплотнение;
- `ActiveMatterState` содержит временно активные обломки, пыль и сыпучую массу.

Минимальная выборка:

```text
MatterSample
    signed_distance_m
    material_composition
    bulk_density_kg_m3
    integrity
    temperature_k
    phase
    flags
```

`signed_distance_m < 0` означает связное вещество, `> 0` — пустоту. Материальный состав и форма хранятся раздельно.

## 5. Неизменяемые архитектурные инварианты

### 5.1. Canonical simulation не содержит scene objects

В snapshots и командах запрещены:

- `Node`;
- `Resource` presentation-типа;
- `Mesh`;
- `Shape3D`;
- `RID`;
- callbacks;
- camera-relative coordinates.

### 5.2. Сохранение массы

Каждая операция формирует mass ledger:

```text
mass_before
mass_remaining_bonded
mass_created_fragments
mass_created_loose
mass_transferred_to_items
mass_vaporized
mass_lost_by_declared_model
mass_after
```

Допустим только явно ограниченный numerical tolerance. Удаление меша без материального результата запрещено как production operation.

### 5.3. Одна авторитетная запись

Matter authority obeys существующие правила:

```text
authority_owner_id
authority_epoch
state_revision
server_tick
operation_id
```

Mesher, physics worker и connectivity worker не являются владельцами состояния.

### 5.4. Независимые LOD

```text
Render LOD      — качество меша и материалов.
Storage LOD     — точность persistent изменения.
Simulation LOD  — глубина активной физики.
Causal LOD      — минимальная точность, которую нельзя потерять без изменения смысла.
```

Выгрузка или удаление визуального mesh не имеет права уничтожить тоннель, месторождение или опору.

### 5.5. Детерминированная процедурная база

Канонический sample определяется только:

```text
body_id
body_generator_id
body_generator_version
body_seed
body-fixed position
feature catalog revision
```

Он не зависит от observer, FPS, текущего render origin или порядка загрузки cells.

## 6. Политики тел

Один домен использует разные `MatterBodyPolicy`.

### 6.1. Small destructible body

Пример: астероид радиусом 1000 м.

Разрешено:

- изменять любой объём;
- делать сквозные тоннели;
- отделять компоненты;
- пересчитывать массу и инерцию;
- создавать новые body aggregates;
- терминально уничтожать исходное тело.

Обязательны:

- глобальный coarse connectivity;
- fragment extraction;
- body lifecycle;
- передача импульса и материала потомкам.

### 6.2. Planetary crust

Пример: Луна.

Разрешено:

- изменять локальный объём коры;
- создавать пещеры, шахты, карьеры и кратеры;
- насыпать и уплотнять материал;
- строить подземные пространства.

По умолчанию запрещено локальной операцией:

- разбить всю планету на rigid bodies;
- материализовать полный объём;
- пересчитывать глобальный inertia tensor после каждого ковша реголита.

Изменения могут обновлять coarse mass summaries, но глобальная планетарная динамика использует отдельную policy и пороги.

## 7. Пространственная адресация вещества

### 7.1. Small-body grid

Для первой лаборатории:

```text
space_id: asteroid-lab-001
grid_id: body-cartesian-octree
grid_revision: 1
root_id: asteroid-lab-001-root
frame_id: body/asteroid-lab-001/fixed
root bounds: [-1024, -1024, -1024] … [1024, 1024, 1024] m
child_capacity: 8
```

`SimulationCellAddress.path` определяет octant path. Matter brick внутри leaf имеет фиксированную sample topology и собственную content revision.

### 7.2. Planetary crust grid

Cube-sphere surface address остаётся индексом внешней поверхности. Для объёма вводится отдельный resolver:

```text
CubeSphere surface cell
+ radial depth interval
→ one or more Matter Simulation Cells
```

Первая версия может использовать roots по cube face или крупной surface zone, но конечный `SpatialCellDescriptor` обязан содержать реальные bounds в `body/moon/fixed`.

Нельзя добавлять `depth` в существующий `PartitionAddress v2` без новой versioned foundation migration.

### 7.3. Shards

Логический body может иметь много shards:

```text
MatterBodyAggregate
├── matter shard surface/f4/17/09/depth/0
├── matter shard surface/f4/17/09/depth/1
├── matter shard cave/...
└── topology summary shard
```

Spatial identity не определяет authority. `AggregateShardDescriptor` связывает shard с cells и отдельным `AggregateAuthorityAddress`.

## 8. Данные и сервисы

Рекомендуемая структура:

```text
scripts/simulation/matter/
├── contracts/
│   ├── matter_sample.gd
│   ├── matter_material_definition.gd
│   ├── matter_body_definition.gd
│   ├── matter_brick_address.gd
│   ├── matter_brick_snapshot.gd
│   ├── matter_mutation_request.gd
│   ├── matter_mutation_result.gd
│   └── matter_mass_ledger.gd
├── generation/
│   ├── matter_sampler_port.gd
│   ├── asteroid_matter_sampler.gd
│   ├── moon_geology_sampler.gd
│   ├── cave_feature_sampler.gd
│   └── mineral_deposit_sampler.gd
├── storage/
│   ├── matter_repository_port.gd
│   ├── sparse_matter_store.gd
│   └── matter_compaction_service.gd
├── mutation/
│   ├── matter_mutation_service.gd
│   ├── excavation_operation.gd
│   ├── deposition_operation.gd
│   └── matter_invariant_validator.gd
├── topology/
│   ├── matter_connectivity_service.gd
│   ├── fragment_extraction_service.gd
│   └── matter_body_lifecycle_service.gd
└── queries/
    ├── matter_query_service.gd
    └── body_surface_query_port.gd
```

Presentation располагается отдельно:

```text
scripts/world/matter/
├── matter_mesh_adapter.gd
├── matter_collision_adapter.gd
├── matter_streaming_manager.gd
├── matter_debug_renderer.gd
└── legacy_moon_surface_adapter.gd
```

## 9. Породы и месторождения

`LunarMaterialLibrary` сейчас является библиотекой визуальных Godot-материалов. Она не должна становиться каталогом физической породы.

Новый `MatterMaterialDefinition` хранит domain properties:

```text
material_id
bulk_density_kg_m3
hardness
compressive_strength_pa
tensile_strength_pa
fracture_toughness
cohesion
abrasiveness
porosity
permeability
heat_capacity_j_kg_k
thermal_conductivity_w_m_k
melting_temperature_k
volatile_fraction
processing_products
```

Presentation adapter отдельно связывает `material_id` с текстурами и shaders.

Месторождение является feature, а не набором заранее записанных вокселей:

```text
MineralDepositFeature
    deposit_id
    feature_type
    host_material_id
    shape_parameters
    grade_field
    impurity_field
    seed
    feature_revision
```

Persistent depletion возникает естественно: excavation сохраняет изменённые bricks и удалённая руда не возвращается.

## 10. Пещеры как генератор пространства

Пещеры генерируются в два шага:

```text
Cave Graph
→ Volume Features
→ SDF subtraction
```

`CaveGraph` содержит:

- chambers;
- corridors;
- shafts;
- entrances;
- fault-guided branches;
- collapsed or sealed sections.

Граф создаётся детерминированно по region address. Геометрия коридора задаётся spline/capsule features, камеры — ellipsoid/superquadric features. Мелкий шум добавляется только после сохранения связности.

Это даёт гарантии, которых нет у чистого 3D-noise:

- заданный вход соединён с камерой;
- можно обеспечить минимальный проход;
- можно поместить месторождение возле ветви;
- можно строить навигационную и sensor модель;
- можно повторить систему по seed.

## 11. Представления вещества

Не всё вещество должно постоянно находиться в SDF.

```text
BONDED_FIELD
→ FRACTURED_FIELD
→ RIGID_FRAGMENT
→ LOOSE_MATTER
→ MATERIAL_BATCH_ITEM
→ CONSTRUCT_COMPONENT
```

И обратные переходы:

```text
MATERIAL_BATCH_ITEM
→ DEPOSITED_LOOSE_MATTER
→ COMPACTED_FILL
→ BONDED_FIELD
```

Правило индивидуализации:

- причинно значимый крупный кусок получает aggregate identity;
- множество мелких обломков агрегируется как parcel;
- спокойная сыпучая масса сворачивается в settled field;
- активная область временно разворачивается в particles или другой local solver.

## 12. API поверхности после интеграции

Текущий API `get_surface_height(direction)` остаётся для:

- atmosphere shell;
- дальнего LOD;
- приблизительной высоты внешней поверхности;
- поиска surface landing region.

Для gameplay вводятся объёмные запросы:

```text
sample_matter(body_id, body_fixed_position)
raycast_matter(body_id, origin, direction, max_distance)
find_nearest_surface(body_id, position, search_radius)
query_clearance(body_id, position, radius)
query_material_column(body_id, origin, direction, distance)
```

Подземный объект нельзя позиционировать через radial altitude. Он хранит обычный `SpatialRef` в body-fixed frame и проверяется через matter queries.

## 13. Миграция текущей Луны

### Шаг 1. Стабильный base sampler

Выделить из текущего генератора observer-independent части:

- macro terrain;
- maria;
- глобальные кратеры;
- massifs;
- детерминированные cell-local features.

Зафиксировать отдельные `generator_id`, `generator_version` и golden samples.

### Шаг 2. A/B presentation proof

Текущий radial mesh строится через новый canonical sampler. Допустимое отличие измеряется автоматически по контрольным направлениям и screenshots. Gameplay и persistence ещё не меняются.

### Шаг 3. Matter overlay bubble

В одном тестовом лунном регионе локальный volumetric mesh заменяет центральную часть старого LOCAL cap. Вне bubble остаётся старый LOCAL/REGIONAL/GLOBAL mesh.

Базовый SDF в bubble выводится из canonical surface:

```text
base_sdf(p) = length(p) - moon_radius - canonical_height(normalize(p))
```

Поверх него применяются cave features и edits.

### Шаг 4. Collision/query switch

Коллизия и mining raycasts внутри bubble переходят на matter adapters. Старый local collision не должен одновременно пересекаться с новым mesh.

### Шаг 5. Persistent edits

Mutation journal и compacted matter bricks сохраняются отдельно от старых persistent entities. Cube-sphere chunk хранит только ссылки/summaries, а не произвольные mesh arrays.

### Шаг 6. Региональное распространение

После seam, persistence и performance gates bubble становится streaming activation region. GLOBAL и REGIONAL mesh продолжают существовать как дешёвое производное представление.

### Шаг 7. Декомпозиция монолита

Только после доказанного parity `procedural_moon_terrain.gd` разделяется на:

- canonical sampler;
- surface mesh adapter;
- matter overlay adapter;
- streaming coordinator;
- materials/rocks presentation;
- compatibility façade.

Полная перепись до A/B proof запрещена: она одновременно меняет генератор, рендер, collision, streaming и gameplay.

## 14. Изолированная лаборатория астероида

Фиксированный экспериментальный мир:

```text
world_id: asteroid_matter_lab
instance_id: scenario-asteroid-matter-lab
body_id: asteroid-lab-001
body_radius_m: 1000.0
body_seed: 2026073101
body_generator_id: asteroid-matter-v1
body_generator_version: 1
body_fixed_frame_id: body/asteroid-lab-001/fixed
space_id: asteroid-lab-001
grid_id: body-cartesian-octree
grid_revision: 1
root_half_extent_m: 1024.0
mean_density_kg_m3: 2400.0
```

Оценочная исходная масса при средней плотности 2400 кг/м³:

```text
≈ 1.0053 × 10^13 кг
```

Оценочная surface gravity:

```text
≈ 0.000671 м/с²
```

Поэтому первая лаборатория использует spectator/jetpack и не подменяет реальную гравитацию лунным значением.

Начальный набор features:

- неправильная ellipsoid/sphere форма;
- крупные вмятины;
- пористые зоны;
- базальтовая матрица;
- железо-никелевая линза;
- ледяной карман;
- одна естественная полость.

Лаборатория обязана запускаться отдельно и не добавляться в `celestial_system.json` до этапа физической интеграции малых тел.

## 15. Что считается полным уничтожением тела

Полное уничтожение не означает удаление одного MeshInstance.

`MatterBodyAggregate` переходит в terminal state только когда:

```text
remaining_bonded_mass <= terminal_bonded_mass_threshold
AND no retained primary connected component
AND all residual mass assigned to fragments, loose matter, items, vapor or declared loss
```

После terminal commit:

- старый body_id больше не принимает mutation;
- потомки получают новые identities;
- mass ledger закрыт;
- persistence не восстанавливает базовое тело;
- old authority routes fenced новой revision/terminal state.

## 16. Антицели

На первых этапах запрещено:

- превращать всю Луну в равномерную voxel array;
- сохранять generated mesh как канонический мир;
- смешивать физический материал с `StandardMaterial3D`;
- мутировать terrain напрямую из UI или инструмента;
- использовать frame-local sphere stamps, зависящие от FPS;
- запускать глобальный granular solver;
- переписывать текущий Moon runtime до отдельного asteroid proof;
- добавлять сетевой protocol fork для matter gameplay.

## 17. Итоговое решение

Текущая поверхность не удаляется немедленно. Она меняет роль:

```text
сейчас:
    height generator = world truth + mesh source + collision source

цель:
    Matter Domain = world truth
    Surface/Mesh/Collision adapters = derived representations
```

Для PlanetSimulator принимается модель:

```text
procedural volume everywhere
+ sparse persistent matter mutations
+ body-specific policies
+ independent storage/render/simulation/causal LOD
+ mass-conserving transactions
+ field ↔ fragment ↔ item ↔ construct transitions
```

Это позволяет сначала безопасно доказать систему на отдельном астероиде, а затем встроить её в наиболее детальные лунные локации без остановки существующей ветки мира.
