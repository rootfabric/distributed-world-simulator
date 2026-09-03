# ECO.EVO7 VIS5.2 — Noncanonical Ground-Cover Bridge Candidate R1

Дата: 2026-09-03  
Статус: IMPLEMENTED / FOCUSED EXACT GREEN / BRANCH EXACT PENDING  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Реализованная граница

VIS5.2 добавляет отдельный presentation-only путь плотного ground cover:

~~~text
ProceduralEarthWorld
  |
  +-- get_surface_state()
  +-- get_surface_point()
  |
  v
VIS5.1 Terrain Surface Frame Adapter
  |
  +-- canonical surface point
  +-- derived geometric terrain normal
  +-- terrain_basis
  +-- derived slope
  |
  v
VIS5.2 Noncanonical Ground-Cover Bridge
  |
  +-- deterministic presentation seed
  +-- grass density / water / snow / geometric-slope filtering
  +-- weighted grass variants
  +-- terrain-normal-aware transforms
  +-- grass MultiMesh batching
  +-- grass mesh/material donor path only
  +-- ground-cover LOD visibility
  |
  X procedural trees
  X biological individuals
  X ecology count meaning
  X fitness meaning
  X mutation meaning
  X Descriptor V2 writes
  X ecology_state_hash writes
~~~

Truth marker:

~~~text
NONCANONICAL_SCENERY
~~~

То есть экземпляры травы сейчас являются визуальным покрытием поверхности, а не скрытой второй ECO population.

## Исправленная orientation boundary

При focused exact прогоне обнаружена и устранена потенциальная ошибка ориентации на неровном terrain.

Неправильный класс решения:

~~~text
already-oriented terrain Basis
  -> world-space Basis.rotated(terrain_normal, yaw)
~~~

может повернуть уже ориентированную Y-ось и дать боковой наклон ground cover.

Принята локальная композиция:

~~~text
terrain_basis
  * local yaw around Vector3.UP
  * local scale
~~~

В коде:

~~~gdscript
var basis := (
    terrain_basis
    * Basis(Vector3.UP, yaw)
    * Basis.from_scale(scale_value)
)
~~~

Таким образом planned transform сохраняет:

~~~text
transform.basis.y.normalized()
  dot terrain_normal
  >= 0.999999
~~~

Это важно для будущего WORLDGEN1, где поверхность может иметь пригорки, овраги, сложные склоны и локально меняющуюся геометрическую нормаль.

## Focused exact evidence

Использован приложенный к проекту canonical Linux double-Godot:

~~~text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

Focused acceptance:

~~~text
ECO.EVO7 VIS5.2 Noncanonical Ground-Cover Bridge:
PASS (57 assertions)
~~~

Проверены:

~~~text
fail-closed setup
deterministic seed/hash
terrain-normal alignment before RenderingServer handoff
grass-only asset boundary
MultiMesh batch counts
LOD visibility
zero-density filtering
water filtering
snow filtering
explicit NONCANONICAL_SCENERY
no tree path
no ecology semantic authority
tamper rejection
~~~

Примечание по headless: dummy RenderingServer не является надёжным readback-источником instance transform после передачи в MultiMesh. Поэтому orientation invariant проверяется на planned Transform3D до MultiMesh handoff, а MultiMesh отдельно проверяется по instance_count / mesh / material / grouping / LOD.

## Durable implementation surfaces

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd

tests/ecology/
  eco_evo7_vis5_2_noncanonical_ground_cover_bridge_acceptance.gd

RUN_ECO_EVO7_VIS5_2_TESTS.sh
RUN_ECO_EVO7_VIS5_2_TESTS.ps1

.github/workflows/
  evo7-vis5-2-noncanonical-ground-cover.yml
~~~

## Formal closure requirement

Focused exact evidence уже GREEN, но VIS5.2 не маркируется CLOSED до полного branch runner:

~~~text
RUN_ECO_EVO7_VIS5_2_TESTS.sh
  |
  +-- VIS5.0 regression
  +-- VIS5.1 regression
  +-- VIS5.2 focused acceptance
~~~

на exact branch HEAD с canonical double-Godot.

После GREEN:

~~~text
VIS5.2 CLOSED
  |
  v
VIS5.3 Mixed-Strata Composition Lab
~~~

Именно VIS5.3 впервые соединит в одной контролируемой visual scene:

~~~text
real uneven terrain
+
VIS4 source-bound evolved PH5 macro plants
+
VIS5.2 dense noncanonical ground cover
+
terrain scenery
~~~

Будущая точка WORLDGEN/ECO остаётся:

~~~text
WORLDGEN1 WG1.7
ECO Surface Field Bridge
~~~

VIS5.2 специально не захватывает эту будущую canonical environmental binding раньше времени.
