# ECO.EVO7 VIS4.6 — Grid Appearance Boundary Ubuntu Verified / CLOSED

Дата: 2026-08-31

Статус:

~~~text
VIS4.6
EXACT UBUNTU DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Canonical executable subject

~~~text
HEAD:
8edc9b9767e8d163b020ac9c7407d385d99bed3b

TREE:
5493dca15e47c23ca939403a98244fd345b37e8b
~~~

Verification checkout:

~~~text
detached HEAD
/home/yurig/distributed-world-simulator/worktrees/eco-vis4-6-verify
~~~

## Godot identity

~~~text
version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Canonical predecessor

The full VIS4.5 canonical chain completed GREEN on the exact VIS4.6 subject.

~~~text
VIS4.5 canonical runner: PASS
VIS4.5 final marker: PRESENT
VIS4.5 focused: PASS / 491 assertions
~~~

The transitive predecessor chain remained GREEN through VIS4.4, VIS4.3, PH5,
VIS4.2, VIS4.1, LS3.6, LS3.4, VIS4.0, PH2 and FFF2.

## VIS4.6 focused acceptance

~~~text
PASS / 796 assertions
~~~

Canonical marker:

~~~text
ECO.EVO7 VIS4.6 Grid Appearance Boundary candidate: PASS
~~~

Canonical runner exit:

~~~text
0
~~~

## Grid appearance evidence

Verified:

~~~text
32x32 Spatial Cohort Lattice preserved

exact VIS2 SHA-256 stable-jitter semantics reused
same record_id -> exact deterministic replay
different record_id -> deterministic appearance variation

x jitter <= +/-0.24 cell
y jitter <= +/-0.15 cell

canonical ecology position preserved:
cell direction -> get_surface_point(direction)

visual position distinct from canonical position
visual position reprojected to real Earth surface

actual PH5 Node3D translation uses visual position
~~~

## Architectural boundary

VIS4.6 preserves the explicit boundary:

~~~text
visual presentation offset
!=
ecological / canonical plant position
~~~

The renderer maintains both:

~~~text
base_world
= canonical ecology cell point

visual_base_world
= presentation-only scattered Earth-surface point
~~~

The accepted canonical position APIs remain source-of-truth APIs.

True continuous physical plant position has not been introduced and remains
reserved for ECO.SPATIAL1.

## Invariants

Verified GREEN:

~~~text
geometry identity preserved
VIS4.5 individuality identity preserved

neutral/lineage color:
grid appearance identity unchanged

render-origin:
canonical world position unchanged
visual world position unchanged
only render coordinates change

LOD TIER0 -> TIER2:
canonical position unchanged
visual position unchanged
appearance_hash unchanged

ecology_state_hash unchanged
~~~

## Authority result

Source guards verified:

~~~text
no process RNG
no biology recomputation
no direct GrowthGraph build in VIS4.6 runtime
no generation authority
no reproduction authority
no mutation authority
no dispersal authority
no persistence authority
no network authority
~~~

## Post-test exactness

~~~text
HEAD unchanged: YES
TREE unchanged: YES
tracked worktree: clean
~~~

## Closure

Canonical VIS4.6 executable boundary:

~~~text
HEAD: 8edc9b9767e8d163b020ac9c7407d385d99bed3b
TREE: 5493dca15e47c23ca939403a98244fd345b37e8b
~~~

Final qualification:

~~~text
VIS4.6 EXACT UBUNTU GREEN
EXACT SUBJECT VERIFIED
EXACT TREE VERIFIED
DOUBLE GODOT VERIFIED
VIS4.5 PREDECESSOR GREEN
VIS4.6 GRID APPEARANCE BOUNDARY GREEN
TRACKED TREE CLEAN

VIS4.6 CLOSED
VIS4.7 MORPHOLOGY INSPECTOR UNBLOCKED
~~~

A separate Windows acceptance gate is not required for this checkpoint.
