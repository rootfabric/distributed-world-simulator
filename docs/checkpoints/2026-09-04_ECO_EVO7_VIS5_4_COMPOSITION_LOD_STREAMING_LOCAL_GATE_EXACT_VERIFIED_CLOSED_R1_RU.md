# ECO.EVO7 VIS5.4 — Composition LOD / Streaming Local Gate EXACT VERIFIED CLOSED R1

Дата: 2026-09-04  
Статус: ACCEPTED / EXACT DOUBLE-GODOT GREEN / CLOSED  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Exact executable subject

~~~text
HEAD:
4b75429ac57b5acd17359ab7f47015cb06e01784

TREE:
3da523fea30f40727eff4d5223a0ac13cd37ada0
~~~

После этого executable subject runtime-код VIS5.4 не изменяется; дальнейшие commits являются только closure/bookkeeping.

## Fresh exact source export

Validation carrier:

~~~text
branch:
validation/eco-vis5-4-source-export-r1

workflow run:
33863307163

result:
SUCCESS

artifact id:
9932951711

exact source tar SHA-256:
85111c8172a7843b800d160234865287c22c05561e02d81b553b4b15264346b5
~~~

Source-export job подтвердил:

~~~text
exact_head=4b75429ac57b5acd17359ab7f47015cb06e01784
exact_tree=3da523fea30f40727eff4d5223a0ac13cd37ada0
~~~

Exact exported implementation hashes:

~~~text
VIS5.4 controller:
f53b2d86b1e88cbf3ad1670cacea41f5b7c24dd3e81ffdc5baf112524562fca4

VIS5.4 acceptance:
ffceba6cfe6348ef73f7494a6cf906d6d39df122d85ab76277937e2684abeac7

Linux runner:
5319e7bbbf56228f63a090cd65de1dc24dfa53cc4ef1083c7349be575a9b356d
~~~

Controller и acceptance в fresh archive побайтно совпали с focused-tested candidate.

## Canonical Godot

~~~text
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Full exact regression

Executed from the fresh exact source archive:

~~~text
RUN_ECO_EVO7_VIS5_4_TESTS.sh

RC=0

full log SHA-256:
5acb77f90bbf19f79486dbcb21702a4c8c0a14c73f68c370a5b112e5dc8aa65e
~~~

Late acceptance chain:

~~~text
VIS4.7 Morphology Inspector                    PASS / 106
VIS4.8 Diversity Evidence                     PASS / 106
VIS4.9 Performance / LOD                      PASS / 116
VIS5.0 Terrain / Ecosystem Composition        PASS / 87
VIS5.1 Terrain Surface Frame Adapter           PASS / 70
VIS5.2 Noncanonical Ground-Cover Bridge        PASS / 57
VIS5.3 Mixed-Strata Composition Lab            PASS / 101
VIS5.4 Composition LOD / Streaming Local Gate  PASS / 92
~~~

The same exact runner preserved the full earlier ECO/PH5 chain, including:

~~~text
FFF2 Morphology Evolution                      PASS / 56
PH2 Environment-Coupled Development           PASS / 107
VIS4.0 Truth / Contract Audit                  PASS / 176
LS3.4 Local Competition                       PASS / 45
LS3.6 Rule Workbench                          PASS / 114
VIS4.1 Source-Bound Morphology Evidence R2    PASS / 598
VIS1 Spatial World Viewer                     PASS / 41
VIS2 Procedural Plant Renderer                PASS / 69
VIS3 Planet Patch / Biome Viewer              PASS / 107
VIS4.2 Honest Diagnostic Morphology           PASS / 1265
PH5 Extensible Materialization                PASS / 720
PH5-S2                                         PASS / 387
PH5-S3 Multi-scale Representation             PASS / 49
PH5-S3 Multiscale Materialization             PASS / 61
PH5-S4 Representation Robustness              PASS / 5026
PH5-S4 Phenotype x Tier Matrix                PASS / 430
VIS4.3 Exact Live Phenotype -> PH5 Bridge     PASS / 752
PLAY0 Live Planet Playground                  PASS / 103
VIS4.4 PLAY0.MORPH                            PASS / 74
VIS4.5 Deterministic Individuality            PASS / 491
VIS4.6 Grid Appearance Boundary               PASS / 796
~~~

## Accepted runtime lifecycle

VIS5.4 materializes a presentation-only control layer over the already accepted VIS5.3 composition:

~~~text
VIS5.3 mixed composition
        |
        +-- accepted VIS4 PH5 projected-size LOD
        +-- VIS5.2 ground-cover visibility gate
        +-- VIS5.3 terrain-rock visibility gate
        +-- render-origin reprojection
        +-- deterministic scenery rebuild
        +-- real ProceduralEarth region rebuild round trip
        |
        v
bounded local visual workload evidence
without ecology truth drift
~~~

### LOD strata

Accepted local modes:

~~~text
NEAR <= 350 m
  PH5: accepted projected-size tiers
  ground cover: visible
  terrain rocks: visible

MID <= 1400 m
  PH5: accepted projected-size tiers
  ground cover: culled
  terrain rocks: visible

FAR <= 7000 m
  PH5: accepted projected-size tiers
  ground cover: culled
  terrain rocks: culled

CULLED > 7000 m
  ground cover: culled
  terrain rocks: culled
  sufficiently distant PH5 records converge to population-only
~~~

Exact acceptance executes:

~~~text
NEAR -> MID -> FAR -> CULLED -> NEAR
~~~

and verifies workload reduction without changing source ecology identity.

VIS5.4 does not create a second macro-plant LOD algorithm: PH5 tier selection remains delegated to the accepted VIS4 renderer.

### Render-origin recenter

Exact acceptance performs:

~~~text
original origin
 -> +1500 m render-origin shift
 -> PH5 render reprojection
 -> same-seed scenery rebuild
 -> restore original origin
 -> same-seed scenery rebuild
~~~

Certified invariants:

~~~text
canonical plant world point unchanged
ecology_state_hash unchanged
Descriptor V2 adapter hash unchanged
PH5 source bridge hash unchanged
original composition hash restored exactly after origin restore
~~~

### Real local-region streaming round trip

The test uses the actual ProceduralEarth local-region API and moves beyond the accepted local recenter threshold:

~~~text
local_recenter_distance_m = 6500 m

target distance > 6500 m

canonical ecology patch
 -> remote prepare_surface_region()
 -> return prepare_surface_region(canonical patch)
 -> original render origin
 -> same-seed scenery regeneration
~~~

Certified:

~~~text
>= 2 real earth_rebuilt events
remote procedural placement suppressed
return procedural placement suppressed
source ecology hash stable
Descriptor V2 adapter identity stable
PH5 bridge identity stable
same-seed / same-region composition hash restored exactly
ecology_identity_drift = false
~~~

During the remote terrain window the local grass/rock scenery is hidden; the canonical PH5 population is not rebound to the remote terrain patch.

## Workload evidence boundary

VIS5.4 exposes:

~~~text
PH5 record count
PH5 visible count
PH5 tier counts
PH5 cost units
PH5 draw-call proxy
ground-cover total / visible count
terrain-rock total / visible count
composition cost proxy
composition draw-call proxy
mode-switch count
render-origin recenter count
render-reprojection count
local-surface rebuild count
scenery rebuild count
region-roundtrip count
frame observations
structural evidence hash
~~~

Important truth boundary:

~~~text
frame timings / FPS = observational only
composition draw-call count = proxy
composition cost = proxy
~~~

These values do not replace renderer truth, PERF2.4, or PERF2.CONV.

## Authority boundary

VIS5.4 owns no:

~~~text
ecology authority
terrain authority
network authority
persistence authority
generation mutation
reproduction / mutation path
procedural-tree biology source
PERF2 authority
~~~

PERF2.CONV remains mandatory before final integrated PLAY1 performance acceptance.

## Procedural-tree exclusion remains intact

Both remote and return ProceduralEarth rebuild summaries preserve:

~~~text
near_trees = 0
billboard_trees = 0
grass = 0
rocks = 0
~~~

for the built-in EarthPlacementSystem path used by VIS5.3 suppression. Canonical VIS4 PH5 remains the only macro-plant presentation stratum.

## Inherited import diagnostics

Fresh Godot import still reports the already-known malformed legacy EVO5 scene files:

~~~text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
~~~

They are not modified or consumed by VIS5.4. After excluding these previously documented inherited diagnostics, the VIS5.4 exact log contains no new SCRIPT ERROR / ERROR findings and the full runner returns RC=0.

## Project Control note

Generic Project Control run:

~~~text
run:
33863271475

result:
FAIL
~~~

The failure was investigated. It comes from the global architecture-ownership compatibility tests and reports existing `CRITICAL_DEPENDENCY_DRIFT` in Matter / registry ownership fingerprints. VIS5.4 files are not present in those findings.

Disposition:

~~~text
GLOBAL CONTROL-PLANE DEBT
NOT A VIS5.4 RUNTIME FALSIFIER
NOT HIDDEN AS GREEN
~~~

Therefore this closure claims only the exact VIS5.4 executable/runtime acceptance described above; it does not claim generic Project Control is green.

## Formal verdict

~~~text
VIS5.4
ACCEPTED
EXACT DOUBLE-GODOT GREEN
CLOSED

required_fixes:
[]
~~~

Next checkpoint:

~~~text
VIS5.5 — Visual Evidence / Integrated PLAY1 Handoff
~~~

Final integrated PLAY1 performance acceptance still requires PERF2.CONV.
