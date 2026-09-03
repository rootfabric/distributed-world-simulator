# ECO.EVO7 VIS5.3 — Mixed-Strata Composition Lab Candidate R1

Дата: 2026-09-03  
Статус: IMPLEMENTED / FOCUSED GREEN / EXACT BRANCH REGRESSION PENDING  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Реализованная сцена

VIS5.3 впервые материализует в одной real-terrain сцене три различающихся по truth-status слоя:

~~~text
ProceduralEarthWorld terrain
        +
CANONICAL_ECO_VIS4_PH5 macro plants
        +
NONCANONICAL_SCENERY ground cover
        +
TERRAIN_SCENERY rocks
~~~

Canonical ecology authority остаётся LS3.6 Rule Workbench. VIS4 Descriptor V2 + reconstruction + PH5 остаются единственным источником macro plants.

## Deterministic visual patch

Default ecology patch seed 360036 был проверен и оказался unsuitable для этой visual composition:

~~~text
grass_density = 0
rocky terrain
~~~

Поэтому VIS5.3 использует отдельный deterministic lab world seed:

~~~text
360055
~~~

Он проходит через тот же RuleWorkbench / ProceduralEarthWorld pipeline и даёт:

~~~text
land
grass_density ≈ 0.786
rock_density > 0
center geometric slope ≈ 6.1 deg
~~~

Это не новый ecology truth source, а воспроизводимый lab fixture, где все strata реально присутствуют.

## Procedural-tree exclusion

ProceduralEarthWorld сам содержит legacy EarthPlacementSystem, который при обычном rebuild мог бы создать procedural trees рядом с canonical PH5 plants.

VIS5.3 до local-region rebuild выставляет:

~~~text
max_near_trees = 0
max_billboard_trees = 0
max_grass_instances = 0
max_rocks = 0
placement subtree hidden
~~~

Таким образом composition scene не маскирует дубликаты visibility-флагом: legacy strata вообще не материализуются.

## Ground cover

VIS5.2 используется без копирования его sampler logic:

~~~text
VIS5.2 GroundCoverBridge
 -> real get_surface_state
 -> VIS5.1 terrain_basis
 -> deterministic seed
 -> MultiMesh grass
 -> NONCANONICAL_SCENERY
~~~

## Rocks

VIS5.3 добавляет отдельный terrain-scenery rock stratum:

~~~text
rock_density
 -> water filter
 -> VIS5.1 geometric slope
 -> terrain_basis
 -> deterministic variant / yaw / scale
 -> EarthAssetLibrary rock mesh/material
 -> MultiMesh
 -> TERRAIN_SCENERY
~~~

Rock scenery не создаёт ecology individuals и не влияет на Descriptor V2 или ecology_state_hash.

## Focused evidence

Canonical project-attached Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

Focused acceptance:

~~~text
ECO.EVO7 VIS5.3 Mixed-Strata Composition Lab:
PASS (101 assertions)
~~~

Focused test использует настоящий ProceduralEarthWorld, настоящий RuleWorkbench и generation 1 exact PH5, а не fake terrain fixture.

Test profile:

~~~text
ground cover = 700
terrain rocks = 60
terrain probes = 9
relief > 10 m
PH5 visible macro plants > 0
~~~

Default visual scene отдельно materialized:

~~~text
PH5 macro plants = 63
ground cover = 4500
terrain rocks = 146
local 220 m relief = 57.246879 m
summary valid = true
~~~

## Durable surfaces

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_3_mixed_strata_composition_lab.gd

scenes/labs/ecology/
  eco_evo7_vis5_3_mixed_strata_composition_lab.tscn

tests/ecology/
  eco_evo7_vis5_3_mixed_strata_composition_lab_acceptance.gd

RUN_ECO_EVO7_VIS5_3_TESTS.sh
RUN_ECO_EVO7_VIS5_3_TESTS.ps1

OPEN_ECO_EVO7_VIS5_3_MIXED_STRATA_LAB.sh
OPEN_ECO_EVO7_VIS5_3_MIXED_STRATA_LAB.ps1

.github/workflows/
  evo7-vis5-3-mixed-strata-composition.yml
~~~

## Closure requirement

До CLOSED требуется fresh exact source export текущего implementation subject и полный:

~~~text
RUN_ECO_EVO7_VIS5_3_TESTS.sh
~~~

на canonical Linux double-Godot.

После exact GREEN:

~~~text
VIS5.3 CLOSED
        |
        v
VIS5.4 Composition LOD / Streaming Local Gate
~~~
