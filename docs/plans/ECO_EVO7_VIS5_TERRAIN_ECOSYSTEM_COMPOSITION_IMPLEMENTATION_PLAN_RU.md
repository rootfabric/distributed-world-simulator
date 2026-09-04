# ECO.EVO7 VIS5 — Terrain / Ecosystem Composition

Статус: VIS5.0 CLOSED / VIS5.1 CLOSED / VIS5.2 CLOSED / VIS5.3 CLOSED / VIS5.4 CURRENT  
Обновлено: 2026-09-04  
Ветка: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1  
Base VIS4 closure: 8f0d6f464e098aa6b8f74ec7e86093cffb6bb1e3  
Exact-tested VIS4.9 subject: ab44617d8961add81a6c9f245c99d0b68eaeab52

## Зачем существует VIS5

VIS4 закрыл честную морфологию отдельных evolved plants:

~~~text
Descriptor V2
 -> exact GrowthGraph reconstruction
 -> PH5
 -> deterministic individuality
 -> terrain-surface placement
 -> LOD/cache
 -> PLAY0 pixels
~~~

VIS5 поднимает уровень задачи от одного растения до цельной локальной сцены:

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

VIS5 остаётся presentation-only линией. Он не меняет PERF2.4 benchmark subject или thresholds. Финальная integrated PLAY1 performance acceptance остаётся за PERF2.CONV.

## Truth / authority boundary

### Canonical macro plants

Единственный macro-plant presentation source в VIS5:

~~~text
VIS4.1 Descriptor V2
+
VIS4.3 exact reconstruction
+
VIS4.4/4.9 PH5 renderer
~~~

Legacy ProceduralEarth procedural trees не должны показываться рядом с ними как будто это одна biological population.

### Terrain

Canonical surface source:

~~~text
ProceduralEarthWorld.get_surface_point(direction)
ProceduralEarthWorld.get_surface_state(direction, lod)
~~~

VIS5 не создаёт второй planet surface и не пишет в terrain truth.

### Ground cover

До отдельного ecology binding dense grass имеет статус только:

~~~text
NONCANONICAL_SCENERY
~~~

Он не имеет population/count/fitness/mutation semantics.

### Rocks

Rocks разрешены как:

~~~text
TERRAIN_SCENERY
~~~

без biological semantics.

## VIS5 implementation ladder

~~~text
VIS5.0 Terrain / Ecosystem Composition Contract Audit       ✅ CLOSED
  |
  v
VIS5.1 Terrain Surface Frame Adapter                        ✅ CLOSED
  |
  v
VIS5.2 Noncanonical Ground-Cover Presentation Bridge       ✅ CLOSED
  |
  v
VIS5.3 Mixed-Strata Composition Lab                         ✅ CLOSED
  |
  v
★ VIS5.4 Composition LOD / Streaming Local Gate ★          🟡 CURRENT
  |
  v
VIS5.5 Visual Evidence / Integrated PLAY1 Handoff           ⬜ BLOCKED
~~~

## VIS5.0 — CLOSED

VIS5.0 зафиксировал authority и donor boundaries до изменения rendering path.

Durable surfaces:

~~~text
config/ecology/eco-evo7-vis5-terrain-ecosystem-composition-audit.v1.json

tests/ecology/eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd

RUN_ECO_EVO7_VIS5_0_TESTS.sh
RUN_ECO_EVO7_VIS5_0_TESTS.ps1
~~~

Ключевые принятые ограничения:

~~~text
VIS4 PH5 remains canonical evolved macro-plant presentation
ProceduralEarth remains terrain source
EarthPlacement grass is presentation donor only
procedural trees forbidden beside VIS4 PH5
EVO4 B6 is legacy presentation donor only
PERF2.4 thresholds untouched
PERF2.CONV remains final integrated performance gate
~~~

## VIS5.1 — CLOSED — Terrain Surface Frame Adapter

VIS5.1 добавил read-only local surface adapter:

~~~text
direction
surface point
surface state
local tangent frame
derived geometric terrain normal
derived slope
~~~

Назначение:

~~~text
macro plants:
retain explicit radial/gravity-up semantics

ground cover:
terrain-normal-aware orientation

rocks:
terrain-normal-aware orientation
~~~

Surface frame не меняет canonical ecology position или plant GrowthGraph.

Closure:

~~~text
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_1_TERRAIN_SURFACE_FRAME_ADAPTER_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~

## VIS5.2 — CLOSED — Noncanonical Ground-Cover Bridge

Executable bridge:

~~~text
ProceduralEarthWorld
  get_surface_state()
  get_surface_point()
        |
        v
VIS5.1 Terrain Surface Frame
        |
        v
VIS5.2 deterministic ground-cover sampler
        |
        +-- grass MultiMesh/assets only
        +-- local yaw around terrain-normal Y
        +-- deterministic generation_hash
        +-- explicit NONCANONICAL_SCENERY
        |
        X no procedural trees
        X no ecology individuals
        X no count / fitness / mutation semantics
        X no Descriptor V2 / ecology_state_hash writes
~~~

Критическая orientation boundary: yaw применяется в локальном terrain frame, а не world-space вращением уже ориентированного Basis. Поэтому planned transform сохраняет Y вдоль derived terrain normal и остаётся пригодным для будущих сложных WORLDGEN-поверхностей.

Exact closure:

~~~text
subject HEAD:
e8ad5ad9f36eba45ff533918c2a97730d766aa17

subject TREE:
31d97747b097146b652a56ba6d5a36c73bdbe496

VIS5.2:
57 / 57 PASS
~~~

Closure:

~~~text
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_2_NONCANONICAL_GROUND_COVER_BRIDGE_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~

## VIS5.3 — CLOSED — Mixed-Strata Composition Lab

VIS5.3 впервые собрал в одной real-terrain сцене:

~~~text
ProceduralEarthWorld terrain
        +
LS3.6 Rule Workbench
        |
        v
VIS4 Descriptor V2 + exact reconstruction
        |
        v
VIS4 PH5 canonical macro plants
        +
VIS5.2 NONCANONICAL_SCENERY ground cover
        +
VIS5.3 TERRAIN_SCENERY rocks
        |
        v
one mixed real-terrain composition
~~~

### Deterministic visual fixture

Default ecology seed 360036 оказался корректным, но визуально неподходящим rocky patch с `grass_density = 0`.

Для mixed-strata lab используется deterministic:

~~~text
world_seed = 360055
~~~

Он проходит через тот же canonical RuleWorkbench / ProceduralEarthWorld path и даёт land patch с dense grass и ненулевой rock density.

### Procedural-tree exclusion

До local-region rebuild legacy EarthPlacementSystem принудительно получает:

~~~text
max_near_trees = 0
max_billboard_trees = 0
max_grass_instances = 0
max_rocks = 0
placement subtree hidden
~~~

Следовательно canonical VIS4 PH5 остаётся единственным macro-plant presentation stratum.

### Default visual profile evidence

~~~text
PH5 macro plants:       63
ground cover:         4500
terrain rocks:         146
local 220m relief:   57.246879 m
max sampled slope:   12.629566 deg
summary valid:        true
~~~

### Exact closure

~~~text
exact executable subject HEAD:
459e533018fa050674aafe91270763bab7e3ec7d

exact executable subject TREE:
77c18ec7ed02de7da9b360be1c3bfb8e035a2306

source-export run:
33757919547 SUCCESS

canonical Godot:
4.7.1.stable.double.custom_build.a13da4feb

RUN_ECO_EVO7_VIS5_3_TESTS.sh:
RC = 0

VIS5.0: 87 / 87 PASS
VIS5.1: 70 / 70 PASS
VIS5.2: 57 / 57 PASS
VIS5.3: 101 / 101 PASS
~~~

Formal closure:

~~~text
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_3_MIXED_STRATA_COMPOSITION_LAB_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~

## VIS5.4 — CURRENT — Composition LOD / Streaming Local Gate

Следующий checkpoint должен проверить уже не факт совместного существования strata, а их runtime lifecycle вокруг движущегося наблюдателя.

Цель:

~~~text
mixed composition
      |
      +-- PH5 macro-plant LOD
      +-- ground-cover visibility / budget
      +-- terrain-scenery visibility / budget
      +-- render-origin recenter
      +-- local region rebuild
      +-- deterministic scenery regeneration
      |
      v
bounded local visual workload
without ecology identity drift
~~~

VIS5.4 должен материализовать и измерить как минимум:

~~~text
visible PH5 plants
ground-cover instance count
terrain-scenery instance count
local draw/workload proxies
LOD transitions
recenter behavior
local surface rebuild behavior
scenery rebuild counts / hashes
frame diagnostics
~~~

Обязательные invariants:

~~~text
recenter must not change ecology_state_hash
recenter must not change Descriptor V2 / PH5 source identity
scenery regeneration must remain deterministic for same seed/region
procedural Earth trees remain suppressed
LOD decisions remain presentation-only
no persistence/network authority
no PERF2.4 threshold changes
~~~

VIS5.4 является local visual gate и не заменяет PERF2.CONV.

## VIS5.5 — BLOCKED — Visual Evidence / PLAY1 Handoff

После VIS5.4 нужно получить graphical evidence mixed ecosystem composition и подготовить workload handoff в integrated PLAY1 gate.

Финальная граница:

~~~text
VIS5 visually ready
+
PERF2.CONV GREEN
 ->
PLAY1 integrated acceptance
~~~

До PERF2.CONV нельзя заявлять итоговую PLAY1 performance acceptance.

## Что специально не делаем

~~~text
не вводим TREE/BUSH/GRASS canonical ecology classes
не делаем decorative grass biological individuals
не заменяем VIS4 morphology старым EVO4 renderer
не включаем procedural Earth trees рядом с VIS4 PH5
не переносим presentation RNG в ecology
не меняем PERF2.4
не открываем ECO.SPATIAL1 раньше его собственного gate
~~~

## Текущий следующий шаг

~~~text
VIS5.0 ✅ CLOSED
VIS5.1 ✅ CLOSED
VIS5.2 ✅ CLOSED
VIS5.3 ✅ EXACT DOUBLE-GODOT GREEN / CLOSED

CURRENT:
★ VIS5.4 Composition LOD / Streaming Local Gate ★

NEXT AFTER GREEN:
VIS5.5 Visual Evidence / Integrated PLAY1 Handoff
~~~
