# ECO.EVO7 VIS5.3 — Mixed-Strata Composition Lab EXACT VERIFIED CLOSED R1

Дата: 2026-09-03  
Статус: ACCEPTED / EXACT DOUBLE-GODOT GREEN / CLOSED  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Exact executable subject

~~~text
HEAD:
459e533018fa050674aafe91270763bab7e3ec7d

TREE:
77c18ec7ed02de7da9b360be1c3bfb8e035a2306
~~~

Exact source export:

~~~text
validation branch:
validation/eco-vis5-3-source-export-r1

run:
33757919547

result:
SUCCESS

source archive SHA-256:
9702c65c7c4d551d901c8619587364dc13a67263973b5c3ec1450e945c6847e6
~~~

The extracted exact implementation files matched the locally focused-tested candidate:

~~~text
VIS5.3 lab script SHA-256:
d4b85b9912a47c2a705715d752b9438f2298975d2f8ab02441970be0c621f887

VIS5.3 acceptance SHA-256:
f32ccc2aabecd12fc34fd66a8cdcb9e3629d4e93fd6a26930aa0a78c7ec87d9c
~~~

## Canonical Godot

~~~text
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Full exact regression

Executed from the fresh source-export archive:

~~~text
RUN_ECO_EVO7_VIS5_3_TESTS.sh

RC=0

full log SHA-256:
7ca81c35f98d8c892c71543698c2f0a439f38e186c497c2a548208b521343d25
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
~~~

The same runner also kept all earlier VIS4/PH5 predecessors GREEN, including PH5-S4 5026/5026 and VIS4.3 752/752.

## Exact default visual profile

The exact exported source was additionally opened with the default VIS5.3 visual profile.

Result:

~~~text
ok=true
summary valid=true

canonical PH5 visible macro plants:
63

VIS5.2 ground cover:
4500

VIS5.3 terrain rocks:
146

9-point local 220 m terrain relief:
57.246879 m

maximum sampled geometric slope:
12.629566 deg

composition hash:
2f887c30fbea1fe175af12748b75f6463e227709f130fdd6e88f1473b4e54819
~~~

Default-profile probe RC:

~~~text
0
~~~

Probe log SHA-256:

~~~text
513e5f3fea2c7129812131c4f555e2dc8ba998220b5e0c1284d8b8b7ae76047c
~~~

## Accepted mixed-strata boundary

VIS5.3 now composes one real surface region as:

~~~text
ProceduralEarthWorld terrain
        |
        +-- canonical surface / local mesh / render origin
        |
        +-- LS3.6 RuleWorkbench
        |       |
        |       v
        |   Descriptor V2 + exact reconstruction
        |       |
        |       v
        |   VIS4 PH5 macro plants
        |
        +-- VIS5.1 terrain frame
        |       |
        |       +-- VIS5.2 grass MultiMeshes
        |       |
        |       +-- VIS5.3 rock MultiMeshes
        |
        v
one mixed composition scene
~~~

Truth statuses remain explicit and non-interchangeable:

~~~text
terrain:
ProceduralEarthWorld

macro plants:
CANONICAL_ECO_VIS4_PH5

ground cover:
NONCANONICAL_SCENERY

rocks:
TERRAIN_SCENERY
~~~

## Deterministic visual fixture

The lab uses world seed 360055.

This was selected because the prior default ecology patch seed 360036 is a legitimate but visually unsuitable rocky/tundra fixture with zero grass density at the ecology patch. Seed 360055 remains inside the same canonical RuleWorkbench / ProceduralEarthWorld path while deterministically producing a grassland composition patch.

The exact local Earth rebuild on 360055 reported:

~~~text
biome:
grassland

local mesh relief:
5428.452480 m

average geometric slope:
7.666243 deg

maximum mesh geometric slope:
33.843475 deg

water fraction:
0.0
~~~

The VIS5.3 local 220 m diagnostic window reports the smaller nearby relief used by the composition summary.

## Procedural-tree exclusion

The legacy ProceduralEarth EarthPlacementSystem is explicitly suppressed before the VIS5.3 local-region rebuild:

~~~text
near trees:
0

billboard trees:
0

legacy grass:
0

legacy rocks:
0

placement subtree:
hidden
~~~

Exact grassland rebuild evidence also recorded:

~~~text
near_trees = 0
billboard_trees = 0
grass = 0
rocks = 0
~~~

Therefore canonical VIS4 PH5 is the only macro-plant presentation stratum in the lab.

## Authority boundary

VIS5.3 does not add:

~~~text
ecology mutation authority
population authority
generation authority
network authority
persistence authority
terrain-write authority
Descriptor V2 write authority
PERF2.4 threshold ownership
~~~

Rebuilding or reseeding scenery changes the presentation composition hash but leaves the canonical ecology hash and PH5 bridge identity unchanged.

## Known inherited diagnostics

Fresh Godot import still reports the already-existing malformed EVO5 scene files:

~~~text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
~~~

These files are not modified or consumed by VIS5.3. The exact VIS5.3 runner and all predecessors still return GREEN.

## Formal verdict

~~~text
VIS5.3
ACCEPTED
EXACT DOUBLE-GODOT GREEN
CLOSED

required_fixes:
[]
~~~

Next checkpoint:

~~~text
VIS5.4 — Composition LOD / Streaming Local Gate
~~~
