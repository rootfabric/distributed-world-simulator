# MW3 — локальный meshing, collision и camera-local laboratory

## 1. Статус и граница

```text
checkpoint: v17.3.0-simulation-mw3-local-meshing
build_id: mw3-local-meshing
base: v17.2.0-simulation-mw2-sparse-bricks / fix1
branch: feature/mw3-local-meshing
status: CANDIDATE FOR INDEPENDENT REVIEW (delivery fix2)
```

MW3 впервые создаёт Godot-представление канонического объёмного астероида MW1/MW2. Источником истины остаётся `MatterBrickSnapshot`; mesh, normals, colors, collision shapes и `Node3D` не входят в canonical matter state и могут быть удалены или перестроены без изменения мира.

MW3 не изменяет Луну, `config/worlds/catalog.json`, production runtime, Item Graph, persistence, network authority и mutation semantics.

## 2. Поток данных

```text
MW1 deterministic volumetric sampler
        ↓
MW2 MatterBrickSnapshot, 11³ samples, ghost border 1
        ↓
MatterTetrahedralMesher
        ↓
MatterBrickMeshData (presentation-only)
        ├── ArrayMesh
        ├── ConcavePolygonShape3D
        └── seam/debug signatures
        ↓
MatterLocalMeshStreamer
        ↓
Matter asteroid laboratory scene
```

Ни один presentation-объект не передаётся обратно в `scripts/simulation/matter/`.

## 3. Алгоритм поверхности

### 3.1 Freudenthal marching tetrahedra

Каждая из `8³` внутренних ячеек brick делится на шесть тетраэдров вокруг диагонали `000 → 111`:

```text
[000, 100, 110, 111]
[000, 100, 101, 111]
[000, 010, 110, 111]
[000, 010, 011, 111]
[000, 001, 101, 111]
[000, 001, 011, 111]
```

Это глобально согласованная Freudenthal-триангуляция. На общей грани соседние кубы выбирают одну и ту же диагональ, поэтому не требуется case-dependent ambiguity resolver Marching Cubes.

Преимущества первой версии:

- таблица состоит из 16 tetra cases, а не 256 cube cases;
- одинаковая триангуляция общих граней;
- локальная перестройка одного brick;
- поддержка внутренних полостей и нависающих поверхностей;
- алгоритм не предполагает heightfield;
- одинаковый код подходит астероиду, пещере и будущей лунной volumetric overlay.

Цена — больше треугольников, чем у хорошо оптимизированного Marching Cubes/Transvoxel. Это допустимо для лабораторного MW3 и не фиксирует окончательный production mesher.

### 3.2 Iso-surface

Первая версия строит поверхность:

```text
signed_distance_m = 0.0
```

Inside rule:

```text
signed_distance_m <= iso_level_m
```

Положение вершины линейно интерполируется по двум SDF samples. Если sample находится на iso-level в пределах `1e-9 m`, используется точная lattice position, чтобы не создавать почти совпадающие вершины.

### 3.3 Локальная система координат

`MatterBrickMeshData.vertices` хранятся относительно центра cell:

```text
body_fixed_vertex = origin_body_local_m + local_vertex
```

Это сохраняет малые координаты vertex buffers и готовит presentation к большим body-fixed пространствам и floating-origin adapters. `origin_body_local_m` выводится из checksum-protected `MatterCellBounds`.

## 4. Нормали

MW2 уже сохраняет одну ghost-полосу с каждой стороны brick. MW3 использует её для центральной производной SDF:

```text
grad_x = (sdf[x + 1] - sdf[x - 1]) / (2 × spacing)
grad_y = (sdf[y + 1] - sdf[y - 1]) / (2 × spacing)
grad_z = (sdf[z + 1] - sdf[z - 1]) / (2 × spacing)
```

Градиент SDF направлен наружу. Нормаль вершины интерполируется между endpoint gradients и нормализуется. Triangle winding проверяется относительно средней interpolated normal. Поскольку Godot считает front face по clockwise-порядку, геометрический cross product индексов должен быть направлен противоположно внешней vertex normal; при необходимости два индекса меняются местами.

Ghost samples важны не только для отсутствия щелей, но и для одинаковых boundary normals соседних bricks.

## 5. Дедупликация и детерминизм

В пределах brick вершина идентифицируется unordered-парой flat lattice sample indices:

```text
edge_key = min(sample_a, sample_b) : max(sample_a, sample_b)
```

Повторное построение одного snapshot создаёт:

- тот же порядок обхода `Z → Y → X` с X-fastest lattice identity;
- те же vertices, normals, colors и indices;
- тот же quantized `content_hash`;
- тот же triangle count.

`MatterBrickMeshData` — presentation contract с Godot packed arrays. Он не JSON-safe и намеренно не является persistence/network DTO. Его `content_hash` нужен для кэша, диагностики и deterministic replay tests, а не для authoritative world history.

## 6. Seam contract

`MatterMeshSeamValidator` сравнивает на общей body-fixed плоскости:

1. уникальный набор boundary vertices;
2. vertex normals, привязанные к boundary positions;
3. уникальный набор boundary segments, извлечённых из triangles.

Наборы квантуются с допуском `1e-6 m` и сортируются. Совпадение только vertex set недостаточно: разные boundary diagonals могли бы создать T-junction. Поэтому MW3 проверяет и segment topology.

`fix1` запрещает ложный успех двух одинаковых пустых наборов. Если ожидаемая общая плоскость не содержит vertices, normals или segments хотя бы с одной стороны, validator возвращает `MATTER_MESH_SEAM_INTERSECTION_MISSING`. Количественные результаты находятся в стандартном envelope `MatterContractUtils.success().details`; focused-тест читает именно `details`, а не несуществующие top-level поля результата.

Focused fixture создаёт два соседних level-1 bricks с аналитическим полем:

```text
sdf(position) = position.y - plane_y
```

Плоскость пересекает общую X-грань. Оба bricks обязаны дать идентичные boundary vertices, normals и segments.

## 7. Материалы

Цвет вершины является временной диагностической projection из dominant material composition:

```text
regolith-compacted → brown-gray
fractured-basalt   → medium gray
basalt             → dark gray
iron-nickel-ore    → dark metallic brown
water-ice          → pale blue
vacuum endpoint    → near-black
```

Цвет не является физическим material state. Будущий renderer сможет заменить vertex colors на tri-planar/virtual-texture material без изменения Matter Domain.

## 8. Collision

`MatterMeshResourceFactory` строит:

```text
ArrayMesh
ConcavePolygonShape3D
MeshInstance3D
StaticBody3D + CollisionShape3D
```

Render mesh и collision получают одну и ту же triangle topology. Для `ConcavePolygonShape3D` включён `backface_collision`, чтобы поверхность ограничивала движение как снаружи тела, так и внутри будущих полостей. Первая версия collision предназначена только для статического локального тела. Динамическое раскалывание астероида, convex decomposition и физика fragments относятся к MW6.

Empty brick:

- имеет валидный `MatterBrickMeshData` со статусом `EMPTY`;
- не создаёт `ArrayMesh`;
- не создаёт collision shape;
- может кэшироваться streamer как resolved-empty.

## 9. Camera-local streamer

`MatterLocalMeshStreamer` реализует ограниченную лабораторную materialization:

- observer position переводится в body-fixed coordinates;
- определяется owning cell заданного level;
- вокруг неё создаётся кубическая область `(2r + 1)³` cells;
- отсутствующие cells помещаются в отсортированную очередь;
- за кадр строится не больше `max_builds_per_frame`;
- запросы имеют generation fence;
- stale queue entries игнорируются;
- bricks вне нового desired set выгружаются;
- empty bricks не материализуются повторно, пока остаются desired;
- неуспешные builds фиксируются отдельно и видны в `failed_brick_count`;
- старые canonical snapshots не изменяются.

`fix1` не читает `global_position` в `configure()`. Observer переводится в body-local пространство через композицию локальных `Transform3D` вдоль общей parent-цепочки observer и streamer. Поэтому первый refresh работает после `add_child()`, даже если `_ready()` ещё не завершён. Разные корни отклоняются с `MW3_STREAMER_OBSERVER_SPACE_MISMATCH`.

`fix2` исправляет идентичность spatial cell: `MatterCellGrid.address_for_position()` возвращает канонический `SimulationCellAddress` с ключом `cell_id`. Streamer использует `cell_id` для observer cell и desired neighborhood. Внутреннее поле очереди сохраняет имя `address_id`, но его значением является стабильный `cell_id`; оно не является полем исходного spatial DTO.

В MW3 sampling, meshing и Godot resource creation выполняются последовательно на main thread с ограничением количества builds за кадр. Это намеренно простая и проверяемая baseline. Worker-thread sampling и staged main-thread resource commit можно добавить после профилирования, не меняя mesh contract.

## 10. Лабораторная сцена

```text
res://scenes/labs/matter_asteroid_meshing_lab.tscn
```

Сцена не регистрируется в production world catalog. Её можно запустить напрямую в редакторе Godot.

Fixture:

```text
body_id: body/asteroid-mw0
reference_radius_m: 1000
seed: 2026073101
default cell level: 5
cell edge: 90.625 m
brick interior resolution: 8³
sample spacing: 11.328125 m
load radius: 1 cell → до 27 desired cells
```

Управление:

```text
WASD   movement
Q/E    down/up
Shift  boost
Esc    capture/release mouse
F      look toward +X asteroid surface
```

UI показывает generation, desired/pending/surface/empty counts, triangles и время последнего brick build.

## 11. Тестовая граница

Focused runner (ожидаемая статическая топология: `7519 assertions`):

```text
RUN_MW3_LOCAL_MESHING_TESTS.ps1
RUN_MW3_LOCAL_MESHING_TESTS.sh
```

Проверяется:

- manifest и неизменность Moon/world catalog;
- аналитический sibling seam;
- реальный MW1 sibling seam через плоскость `Y = 0`;
- boundary vertex и segment equality;
- deterministic mesh replay;
- finite vertices;
- unit normals;
- Godot-clockwise triangle winding относительно внешних vertex normals;
- реальный MW1 surface brick;
- empty interior и vacuum bricks;
- ArrayMesh projection;
- ConcavePolygonShape3D projection;
- presenter origin и node topology;
- camera-local desired set;
- generation fence при перемещении observer;
- corrupted snapshot/grid/iso/hash/normal/color/bounds rejection;
- boundary-normal mismatch rejection.

Regression gate:

```text
MW3 focused
MW2 7470 assertions
MW1 3685 assertions
MW0 2011 assertions
A3 12/12
M6 10/10
git diff --check
```

## 12. Не входит в MW3

```text
terrain mutations and drilling
persistent edited bricks
Item Graph mass transfer
network authority
Moon overlay
full asteroid global mesh
LOD transition meshing
Transvoxel
fragmentation
loose matter
GPU meshing
worker-thread resource creation
production world catalog integration
```

Следующий этап MW4 получает уже существующую цепочку `snapshot → mesh/collision` и должен инвалидировать только bricks, revision которых изменилась после authoritative excavation/deposition transaction.
