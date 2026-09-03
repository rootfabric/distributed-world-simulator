# ECO.EVO7 VIS5.1 — Terrain Surface Frame Adapter Candidate R1

Дата: 2026-09-03  
Статус: IMPLEMENTED / LOCAL EXACT-GODOT FOCUSED GREEN / UBUNTU FULL EXACT PENDING  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Purpose

VIS5.1 adds one read-only terrain surface-frame adapter between the accepted ProceduralEarthWorld surface APIs and future VIS5 ground-cover/terrain-scenery presentation.

It does not alter accepted VIS4 macro-plant placement.

## New executable surface

~~~text
scripts/labs/ecology/
  eco_evo7_vis5_1_terrain_surface_frame_adapter.gd
~~~

The adapter consumes only:

~~~text
ProceduralEarthWorld.get_planet_radius()
ProceduralEarthWorld.get_surface_point()
ProceduralEarthWorld.get_surface_state()
~~~

and emits:

~~~text
canonical_direction
surface_point_world
surface_state
elevation_m

radial_up
radial_basis

derived terrain_normal
terrain_basis
slope_deg

frame_hash
~~~

## Critical separation

Two frames are explicit:

~~~text
radial_basis
= gravity/radial-up semantics
= remains suitable for accepted macro-plant orientation

terrain_basis
= derived geometric surface-normal semantics
= future ground-cover / rocks presentation
~~~

Therefore:

~~~text
terrain normal
!= canonical ecology position

terrain basis
!= GrowthGraph mutation

terrain slope
!= biology input
~~~

## Geometric derivation

At one canonical direction, the adapter samples four nearby canonical terrain surface points:

~~~text
+x tangent
-x tangent
+z tangent
-z tangent
~~~

using an angular step derived from:

~~~text
sample_distance_m / planet_radius_m
~~~

The geometric terrain normal is derived from the two surface chords and forced outward relative to radial-up.

The terrain frame is then orthonormalized and sealed.

## Fail-closed conditions

The adapter rejects:

~~~text
null/incompatible earth source
zero/non-finite direction
invalid sample distance
negative LOD
invalid planet radius
non-Vector3 surface points
non-Dictionary surface state
non-finite geometry
degenerate surface chords
invalid derived basis
~~~

The validator additionally rejects tampered slope, authority flags, basis or frame hash.

## Focused acceptance

~~~text
tests/ecology/
  eco_evo7_vis5_1_terrain_surface_frame_adapter_acceptance.gd
~~~

The deterministic fixture proves:

~~~text
invalid inputs fail closed

flat surface:
terrain normal ~= radial up
slope ~= 0

sloped surface:
terrain normal differs from radial up
slope is materially non-zero
radial and terrain frames remain distinct

same source + same sampling:
same terrain normal
same slope
same frame hash

changed sample distance:
changed frame identity

tampered slope:
REJECT

tampered canonical-position flag:
REJECT

tampered frame hash:
REJECT
~~~

Source guards prove VIS5.1 does not import Descriptor V2, recompute GrowthGraph, or modify accepted VIS4 macro-plant placement.

## Local canonical-Godot focused execution

The project-attached canonical Linux double-Godot was used:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

A minimal execution project containing the exact new adapter and focused runtime fixture completed:

~~~text
VIS5.1 focused:
PASS / 70 assertions

derived sloped fixture:
5.71058179183504 deg

RC:
0
~~~

This is parser/runtime/math evidence only. It does not replace the full repository predecessor-chain exact run.

## Canonical runners

~~~text
RUN_ECO_EVO7_VIS5_1_TESTS.sh
RUN_ECO_EVO7_VIS5_1_TESTS.ps1
~~~

They execute:

~~~text
VIS5.0 closed predecessor regression
+
VIS5.1 focused acceptance
~~~

## Exact gate

~~~text
.github/workflows/
  evo7-vis5-1-terrain-surface-frame.yml
~~~

Required runner labels:

~~~text
self-hosted
Linux
X64
~~~

The known Ubuntu host currently has no registered GitHub Actions runner, so queued workflow state is an infrastructure condition rather than an implementation verdict.

## Candidate verdict

~~~text
VIS5.1 IMPLEMENTED
FOCUSED EXACT-GODOT GREEN

full predecessor-chain exact verification:
PENDING
~~~

No formal closure is claimed yet.

Next after full GREEN:

~~~text
VIS5.2 — Noncanonical Ground-Cover Presentation Bridge
~~~
