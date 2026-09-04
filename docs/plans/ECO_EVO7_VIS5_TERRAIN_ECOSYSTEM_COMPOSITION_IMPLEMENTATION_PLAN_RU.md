# ECO.EVO7 VIS5 — Terrain / Ecosystem Composition

Статус: VIS5.0 CLOSED / VIS5.1 CLOSED / VIS5.2 CLOSED / VIS5.3 CLOSED / VIS5.4 CLOSED / VIS5.5 CURRENT  
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

VIS5 поднимает задачу от одного растения до цельной локальной сцены:

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
+
visual evidence / PLAY1 handoff
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

Legacy ProceduralEarth procedural trees не показываются рядом с ними как будто это одна biological population.

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
VIS5.4 Composition LOD / Streaming Local Gate               ✅ CLOSED
  |
  v
★ VIS5.5 Visual Evidence / Integrated PLAY1 Handoff ★       🟡 CURRENT
~~~

## VIS5.0 — CLOSED

VIS5.0 зафиксировал authority и donor boundaries до изменения rendering path.

Ключевые ограничения:

~~~text
VIS4 PH5 remains canonical evolved macro-plant presentation
ProceduralEarth remains terrain source
EarthPlacement grass is presentation donor only
procedural trees forbidden beside VIS4 PH5
EVO4 B6 is legacy presentation donor only
PERF2.4 thresholds untouched
PERF2.CONV remains final integrated performance gate
~~~

Durable surfaces:

~~~text
config/ecology/eco-evo7-vis5-terrain-ecosystem-composition-audit.v1.json
tests/ecology/eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd
RUN_ECO_EVO7_VIS5_0_TESTS.sh
RUN_ECO_EVO7_VIS5_0_TESTS.ps1
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

Критическая orientation boundary: yaw применяется в локальном terrain frame, а не world-space вращением уже ориентированного Basis. Поэтому planned transform сохраняет Y вдоль derived terrain normal и пригоден для будущих сложных WORLDGEN-поверхностей.

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

Default ecology seed 360036 корректен, но visual patch имеет `grass_density = 0`.

Для mixed-strata lab используется deterministic:

~~~text
world_seed = 360055
~~~

Он проходит через тот же canonical RuleWorkbench / ProceduralEarthWorld path и даёт land patch с dense grass и ненулевой rock density.

### Procedural-tree exclusion

До local-region rebuild legacy EarthPlacementSystem получает:

~~~text
max_near_trees = 0
max_billboard_trees = 0
max_grass_instances = 0
max_rocks = 0
placement subtree hidden
~~~

Canonical VIS4 PH5 остаётся единственным macro-plant presentation stratum.

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

## VIS5.4 — CLOSED — Composition LOD / Streaming Local Gate

VIS5.4 сертифицировал runtime lifecycle mixed composition вокруг движущегося наблюдателя без изменения ecology truth.

Executable controller:

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_4_composition_lod_streaming_gate.gd
~~~

Acceptance:

~~~text
tests/ecology/
  eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd
~~~

### Accepted composition modes

~~~text
NEAR <= 350 m
  PH5 projected-size LOD
  ground cover visible
  rocks visible

MID <= 1400 m
  PH5 projected-size LOD
  ground cover culled
  rocks visible

FAR <= 7000 m
  PH5 projected-size LOD
  ground cover culled
  rocks culled

CULLED > 7000 m
  ground cover culled
  rocks culled
  sufficiently distant PH5 -> population-only
~~~

PH5 tier selection остаётся делегированным accepted VIS4 renderer; VIS5.4 не вводит второй plant LOD model.

### Runtime lifecycle proven

Exact acceptance выполняет:

~~~text
NEAR -> MID -> FAR -> CULLED -> NEAR
~~~

и проверяет уменьшение visual workload proxies при неизменном ecology source identity.

Render-origin lifecycle:

~~~text
original origin
 -> +1500 m shift
 -> PH5 render reprojection
 -> same-seed scenery rebuild
 -> restore original origin
 -> same-seed rebuild
 -> exact original composition hash restored
~~~

Certified invariants:

~~~text
canonical plant world point unchanged
ecology_state_hash unchanged
Descriptor V2 adapter hash unchanged
PH5 source bridge hash unchanged
procedural Earth tree placement remains suppressed
~~~

Real local-region streaming lifecycle:

~~~text
local_recenter_distance_m = 6500 m

target > 6500 m

canonical patch
 -> remote prepare_surface_region()
 -> canonical prepare_surface_region()
 -> original render origin
 -> same-seed scenery rebuild
~~~

Certified:

~~~text
>= 2 real earth_rebuilt events
remote placement suppressed
return placement suppressed
source identity stable
same-seed/same-region composition hash restored exactly
ecology_identity_drift = false
~~~

### Workload diagnostics

VIS5.4 exposes presentation-only diagnostics:

~~~text
PH5 record / visible / tier counts
PH5 cost units / draw-call proxy
ground-cover total / visible count
terrain-rock total / visible count
composition cost proxy
composition draw-call proxy
mode switches
render-origin recenter / reprojection counts
local-surface rebuild count
scenery rebuild count
region-roundtrip count
frame observations
structural evidence hash
~~~

Frame timing/FPS are observational only. Cost/draw-call values are explicit proxies, not renderer truth or PERF2 acceptance.

### Exact closure

~~~text
exact executable subject HEAD:
4b75429ac57b5acd17359ab7f47015cb06e01784

exact executable subject TREE:
3da523fea30f40727eff4d5223a0ac13cd37ada0

source-export run:
33863307163 SUCCESS

artifact:
9932951711

source tar SHA-256:
85111c8172a7843b800d160234865287c22c05561e02d81b553b4b15264346b5

canonical Godot:
4.7.1.stable.double.custom_build.a13da4feb

RUN_ECO_EVO7_VIS5_4_TESTS.sh:
RC = 0

full log SHA-256:
5acb77f90bbf19f79486dbcb21702a4c8c0a14c73f68c370a5b112e5dc8aa65e

VIS5.0: 87 / 87 PASS
VIS5.1: 70 / 70 PASS
VIS5.2: 57 / 57 PASS
VIS5.3: 101 / 101 PASS
VIS5.4: 92 / 92 PASS
~~~

Formal closure:

~~~text
docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_4_COMPOSITION_LOD_STREAMING_LOCAL_GATE_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~

Generic Project Control remains separately red on pre-existing global Matter/registry architecture-ownership dependency drift; VIS5.4 files are not in those findings. Это фиксируется как внешний control-plane debt и не объявляется GREEN.

## VIS5.5 — CURRENT — Visual Evidence / Integrated PLAY1 Handoff

VIS5.5 должен превратить уже доказанный mixed composition runtime в законченный graphical evidence / integration handoff.

Цель:

~~~text
VIS5.3 mixed real-terrain composition
+
VIS5.4 bounded LOD / streaming lifecycle
        |
        v
repeatable graphical evidence
+
operator-readable scene state
+
PLAY1 workload handoff package
~~~

Минимальный scope VIS5.5:

~~~text
1. graphical scene evidence of all accepted strata:
   - real uneven terrain
   - canonical VIS4 PH5 macro plants
   - NONCANONICAL_SCENERY ground cover
   - TERRAIN_SCENERY rocks

2. evidence of LOD/streaming modes:
   - NEAR
   - MID
   - FAR / CULLED where visually meaningful
   - render-origin / local-region transition evidence

3. operator-readable truth labels:
   - what is canonical ecology
   - what is noncanonical scenery
   - what is terrain scenery
   - what counters are proxies

4. durable evidence / runner / capture path suitable for PLAY1 handoff

5. no widening of authority:
   - no ecology writes
   - no terrain writes
   - no network/persistence authority
   - no PERF2 threshold ownership
~~~

### Final join boundary

VIS5.5 GREEN means:

~~~text
VIS5 visual composition line is ready for handoff
~~~

It does NOT by itself mean final PLAY1 performance acceptance.

The final join remains:

~~~text
VIS5.5 GREEN
+
PERF2.CONV GREEN
        |
        v
PLAY1 integrated acceptance
~~~

## Что специально не делаем

~~~text
не вводим TREE/BUSH/GRASS canonical ecology classes
не делаем decorative grass biological individuals
не заменяем VIS4 morphology старым EVO4 renderer
не включаем procedural Earth trees рядом с VIS4 PH5
не переносим presentation RNG в ecology
не меняем PERF2.4
не объявляем PLAY1 performance accepted до PERF2.CONV
не открываем ECO.SPATIAL1 раньше его собственного gate
~~~

## Текущий следующий шаг

~~~text
VIS5.0 ✅ CLOSED
VIS5.1 ✅ CLOSED
VIS5.2 ✅ CLOSED
VIS5.3 ✅ EXACT DOUBLE-GODOT GREEN / CLOSED
VIS5.4 ✅ EXACT DOUBLE-GODOT GREEN / CLOSED

CURRENT:
★ VIS5.5 Visual Evidence / Integrated PLAY1 Handoff ★

FINAL JOIN AFTER VIS5.5:
PERF2.CONV + PLAY1 integrated acceptance
~~~

## Durable closures

~~~text
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_0_TERRAIN_ECOSYSTEM_COMPOSITION_UBUNTU_VERIFIED_CLOSED_R1_RU.md
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_1_TERRAIN_SURFACE_FRAME_ADAPTER_EXACT_VERIFIED_CLOSED_R1_RU.md
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_2_NONCANONICAL_GROUND_COVER_BRIDGE_EXACT_VERIFIED_CLOSED_R1_RU.md
docs/checkpoints/2026-09-03_ECO_EVO7_VIS5_3_MIXED_STRATA_COMPOSITION_LAB_EXACT_VERIFIED_CLOSED_R1_RU.md
docs/checkpoints/2026-09-04_ECO_EVO7_VIS5_4_COMPOSITION_LOD_STREAMING_LOCAL_GATE_EXACT_VERIFIED_CLOSED_R1_RU.md
~~~
