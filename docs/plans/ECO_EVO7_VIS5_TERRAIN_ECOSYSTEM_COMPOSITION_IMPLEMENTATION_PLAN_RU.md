# ECO.EVO7 VIS5 — Terrain / Ecosystem Composition

Статус: VIS5.0 CLOSED / VIS5.1 CLOSED / VIS5.2 CURRENT  
Дата: 2026-09-03  
Ветка: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1  
Base VIS4 closure: 8f0d6f464e098aa6b8f74ec7e86093cffb6bb1e3  
Exact-tested VIS4.9 subject: ab44617d8961add81a6c9f245c99d0b68eaeab52

## Зачем открывается VIS5

VIS4 завершил честную морфологию отдельных evolved plants:

~~~text
Descriptor V2
 -> exact GrowthGraph reconstruction
 -> PH5
 -> deterministic individuality
 -> terrain-surface placement
 -> LOD/cache
 -> PLAY0 pixels
~~~

Следующая визуальная проблема уже не форма одного растения, а композиция сцены:

~~~text
неровный ProceduralEarth terrain
+
source-bound evolved PH5 plants
+
плотный ground cover
+
terrain scenery
+
LOD / streaming
~~~

VIS5 не является продолжением PERF2.4 и не меняет его benchmark subject или thresholds.

VIS5 может разрабатываться параллельно PERF2.4, пока остаётся отдельной presentation-only линией. Финальная PLAY1 performance acceptance всё равно остаётся за PERF2.CONV.

## Что уже есть и что важно не перепутать

### 1. VIS4 уже стоит на реальном terrain

Текущий PH5 renderer использует:

~~~text
earth_world.get_surface_point(up)
earth_world.get_surface_point(visual_direction)
~~~

Поэтому evolved plants уже получают реальную terrain elevation, включая VIS4.6 visual scatter.

VIS5 не должен изобретать второй planet surface.

### 2. Старый dense grass donor существует

~~~text
scripts/world/vegetation/earth_placement_system.gd
~~~

Он уже умеет:

~~~text
grass density sampling
 -> local disk placement
 -> terrain surface point
 -> grass asset selection
 -> MultiMesh batching
 -> LOD visibility
~~~

Это полезный технический donor для VIS5.

Но его grass source:

~~~text
ProceduralEarth pipeline grass_density
+
presentation RNG
~~~

не является ECO.EVO7 evolved population truth.

Следовательно до отдельного ecology binding этот grass можно использовать только как:

~~~text
NONCANONICAL SURFACE SCENERY
~~~

а не как biological individuals.

### 3. Procedural trees нельзя включать рядом с VIS4 PH5

EarthPlacementSystem также создаёт procedural trees через tree_density.

В VIS5 это запрещено до отдельного source-binding решения:

~~~text
VIS4 PH5 evolved plant
!=
procedural Earth tree decoration
~~~

Одновременный показ обоих путей как одной живой популяции дал бы визуальное удвоение и ложную ecology truth.

Поэтому ближайшая смешанная сцена должна иметь:

~~~text
macro plants:
VIS4 PH5 only

ground cover:
explicitly noncanonical scenery

rocks:
terrain scenery

terrain:
ProceduralEarthWorld
~~~

### 4. Старый ECO.EVO4 B6 — только presentation donor

~~~text
scripts/labs/ecology/eco_evo4_b6_region_lab.gd
~~~

Он полезен как пример:

~~~text
dense per-variant batching
MultiMesh composition
rich visual region
~~~

Но он основан на старом manifest и PlaneMesh-ground, поэтому не может быть текущим ECO.EVO7 source.

## VIS5 implementation ladder

~~~text
VIS5.0 Terrain / Ecosystem Composition Contract Audit
  |
  v
VIS5.1 Terrain Surface Frame Adapter
  |
  v
VIS5.2 Noncanonical Ground-Cover Presentation Bridge
  |
  v
VIS5.3 Mixed-Strata Composition Lab
  |
  v
VIS5.4 Composition LOD / Streaming Local Gate
  |
  v
VIS5.5 Visual Evidence / Integrated PLAY1 Handoff
~~~

## VIS5.0 — CLOSED

VIS5.0 фиксирует authority и donor boundaries до изменения rendering path.

Durable surfaces:

~~~text
config/ecology/
  eco-evo7-vis5-terrain-ecosystem-composition-audit.v1.json

tests/ecology/
  eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd

RUN_ECO_EVO7_VIS5_0_TESTS.sh
RUN_ECO_EVO7_VIS5_0_TESTS.ps1
~~~

Exit criteria:

~~~text
VIS4.9 predecessor regression GREEN

VIS5.0 focused GREEN

VIS4 PH5 remains canonical evolved macro-plant presentation

ProceduralEarth remains terrain source

EarthPlacement grass accepted only as presentation donor

procedural trees explicitly forbidden in VIS5 composition

EVO4 B6 accepted only as legacy presentation donor

PERF2.4 thresholds untouched

PERF2.CONV remains final integrated performance gate
~~~

## VIS5.1 — CLOSED — Terrain Surface Frame Adapter

После VIS5.0 GREEN следующий кодовый checkpoint должен добавить один read-only surface adapter.

Он должен получать из ProceduralEarthWorld:

~~~text
direction
surface point
surface state
local tangent frame
derived geometric terrain normal
derived slope
~~~

и возвращать только presentation data.

Зачем это нужно:

~~~text
tree-like macro plants:
gravity/radial-up semantics remain explicit

grass / low ground cover:
may use terrain-normal-aware presentation orientation

rocks:
may use terrain-normal-aware orientation
~~~

Surface normal не должен менять canonical ecology position или plant GrowthGraph.

## VIS5.2 — Noncanonical Ground-Cover Presentation Bridge

Первый practical visual bridge должен переиспользовать grass MultiMesh/assets из EarthPlacementSystem, но вынести ground-cover path отдельно от procedural trees.

Обязательные свойства:

~~~text
grass only
no procedural trees
terrain-following
deterministic/replayable presentation seed
explicit NONCANONICAL_SCENERY marker
no ecology count/fitness/mutation meaning
no effect on Descriptor V2 or ecology_state_hash
~~~

## VIS5.3 — Mixed-Strata Composition Lab

Цель:

~~~text
real uneven Earth terrain
+
VIS4 evolved PH5 plants
+
dense grass ground cover
+
rocks / terrain scenery
~~~

В этой точке уже можно будет визуально оценивать развитую экосистему на неровном ландшафте без подмены biology декоративной растительностью.

## VIS5.4 — Local LOD / Streaming

VIS5-local gate может измерять:

~~~text
visible PH5 plants
grass instance count
terrain scenery count
local draw workload
LOD transitions
recenter/rebuild behavior
visual frame diagnostics
~~~

Но он не меняет и не заменяет PERF2.CONV.

## VIS5.5 — Visual Evidence / Handoff

VIS5.5 должен дать graphical evidence mixed ecosystem composition и передать готовую visual workload сторону в integrated PLAY1 gate.

Финальная граница:

~~~text
VIS5 visually ready
+
PERF2.CONV GREEN
 ->
PLAY1 integrated acceptance
~~~

До PERF2.CONV нельзя заявлять, что итоговый PLAY1 performance принят.

## Что пока специально не делаем

~~~text
не вводим TREE/BUSH/GRASS canonical ecology classes
не делаем декоративные grass instances biological individuals
не заменяем VIS4 morphology старым EVO4 renderer
не включаем procedural Earth trees рядом с VIS4 PH5
не переносим presentation RNG в ecology
не меняем PERF2.4
не открываем ECO.SPATIAL1 раньше его собственного gate
~~~

## Текущий следующий шаг

~~~text
VIS5.0 ✅ ACCEPTED / UBUNTU EXACT GREEN / CLOSED
VIS5.1 ✅ ACCEPTED / EXACT DOUBLE-GODOT GREEN / CLOSED

CURRENT:
VIS5.2 Noncanonical Ground-Cover Presentation Bridge
~~~

Durable closures:

~~~text
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_0_TERRAIN_ECOSYSTEM_COMPOSITION_UBUNTU_VERIFIED_CLOSED_R1_RU.md
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_1_TERRAIN_SURFACE_FRAME_ADAPTER_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~
