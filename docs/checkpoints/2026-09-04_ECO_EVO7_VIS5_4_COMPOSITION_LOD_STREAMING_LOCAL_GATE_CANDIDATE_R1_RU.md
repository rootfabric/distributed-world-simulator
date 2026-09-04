# ECO.EVO7 VIS5.4 — Composition LOD / Streaming Local Gate Candidate R1

Дата: 2026-09-04  
Статус: IMPLEMENTED / FOCUSED GREEN / EXACT BRANCH REGRESSION PENDING  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Реализованная граница

VIS5.4 добавляет presentation-only controller поверх уже закрытого VIS5.3 и не изменяет его executable subject.

~~~text
VIS5.3 mixed composition
        |
        +-- VIS4 PH5 projected-size LOD
        +-- VIS5.2 ground-cover visibility gate
        +-- VIS5.3 rock visibility gate
        +-- render-origin reprojection
        +-- deterministic scenery rebuild
        +-- ProceduralEarth local-region rebuild round trip
        |
        v
bounded local visual workload evidence
without ecology identity drift
~~~

## Composition modes

~~~text
NEAR    <= 350 m
  PH5 projected-size LOD
  ground cover visible
  terrain rocks visible

MID     <= 1400 m
  PH5 projected-size LOD
  ground cover culled
  terrain rocks visible

FAR     <= 7000 m
  PH5 projected-size LOD
  ground cover culled
  terrain rocks culled

CULLED  > 7000 m
  PH5 converges to population-only at sufficiently large distance
  ground cover culled
  terrain rocks culled
~~~

The gate delegates PH5 tier selection to the already accepted VIS4 renderer; it does not create a second plant LOD model.

## Render-origin lifecycle

Explicit recenter:

~~~text
set_render_origin(new origin)
 -> PH5 refresh_render_transform()
 -> VIS5.3 deterministic scenery rebuild with same seed
 -> restore stratum visibility
~~~

Required invariant:

~~~text
canonical plant world point unchanged
ecology_state_hash unchanged
Descriptor V2 adapter hash unchanged
PH5 source bridge hash unchanged
~~~

A shift followed by restoring the original render origin must restore the exact VIS5.3 composition hash for the same seed/region.

## Local surface streaming lifecycle

The focused acceptance performs a real ProceduralEarth region round trip beyond the accepted local recenter threshold:

~~~text
local_recenter_distance_m = 6500 m

target distance > 6500 m

canonical patch
 -> remote prepare_surface_region()
 -> canonical patch prepare_surface_region()
 -> original render origin
 -> same-seed scenery rebuild
~~~

While the remote terrain window is active, local grass/rock scenery is hidden. Canonical PH5 ecology truth is not rebound to the remote terrain region.

After return:

~~~text
source ecology identity exact
PH5 bridge identity exact
Descriptor V2 source exact
same-seed composition hash exact
procedural Earth placement remains 0/0/0/0
~~~

## Diagnostics

The gate exposes:

~~~text
PH5 record / visible counts
PH5 tier counts
PH5 cost units
PH5 draw-call proxy
ground-cover total / visible count
rock total / visible count
composition cost proxy
composition draw-call proxy
observer / mode transition counts
render-origin recenter count
render reprojection count
local surface rebuild count
scenery rebuild count
region roundtrip count
frame observations
structural evidence hash
~~~

Frame timings/FPS remain observational only. Draw/workload counters are explicitly proxies and are not renderer draw-call truth or PERF2 acceptance.

## Authority boundary

VIS5.4 owns no:

~~~text
ecology authority
terrain authority
network authority
persistence authority
PERF2 authority
generation mutation
reproduction / mutation path
procedural-tree source
~~~

PERF2.CONV remains required for final integrated PLAY1 performance acceptance.

## Focused evidence

Canonical attached Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

Focused real-runtime acceptance:

~~~text
ECO.EVO7 VIS5.4 Composition LOD / Streaming Local Gate:
PASS (92 assertions)
~~~

The acceptance uses real VIS5.3 / ProceduralEarthWorld / RuleWorkbench generation-1 PH5, not a fake streaming world.

## Durable surfaces

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_4_composition_lod_streaming_gate.gd

tests/ecology/
  eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd

RUN_ECO_EVO7_VIS5_4_TESTS.sh
RUN_ECO_EVO7_VIS5_4_TESTS.ps1

.github/workflows/
  evo7-vis5-4-composition-lod-streaming.yml
~~~

## Closure requirement

Before CLOSED:

~~~text
fresh exact source export
+
RUN_ECO_EVO7_VIS5_4_TESTS.sh
+
canonical Linux double-Godot
+
VIS5.0 .. VIS5.4 all GREEN
~~~

After exact GREEN:

~~~text
VIS5.4 CLOSED
        |
        v
VIS5.5 Visual Evidence / Integrated PLAY1 Handoff
~~~
