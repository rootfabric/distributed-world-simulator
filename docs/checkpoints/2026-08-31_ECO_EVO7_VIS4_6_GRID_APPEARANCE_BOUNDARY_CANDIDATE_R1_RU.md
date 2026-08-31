# ECO.EVO7 VIS4.6 — Grid Appearance Boundary R1 Candidate

Дата: 2026-08-31

Статус:

~~~text
VIS4.6 R1
EXACT UBUNTU DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Frozen executable subject

~~~text
HEAD:
8edc9b9767e8d163b020ac9c7407d385d99bed3b

TREE:
5493dca15e47c23ca939403a98244fd345b37e8b
~~~

Predecessor:

~~~text
VIS4.5 CLOSED
canonical executable:
1389c897d5a17ab0986e0c1d65602d705479e859
~~~

## Goal

VIS4.6 removes the obvious visual cell-center regularity without changing
ecological position semantics.

Canonical rule:

~~~text
visual presentation offset
!=
ecological / canonical plant position
~~~

The 32x32 Spatial Cohort Lattice remains ecology truth.

True continuous physical plant positions are still reserved for:

~~~text
ECO.SPATIAL1
~~~

## Reused VIS2 semantics

Accepted VIS2 already uses stable deterministic record jitter:

~~~text
token = record_id.sha256_text()

ux = first 24 bits / 16777215
uy = next 24 bits / 16777215

x = (ux - 0.5) * 0.48 cell
y = (uy - 0.5) * 0.30 cell
~~~

Therefore VIS4.6 does not invent a second scatter convention.

Exact bounds:

~~~text
x: +/- 0.24 cell
y: +/- 0.15 cell
~~~

## 3D mapping

VIS4.6 maps the accepted VIS2 fractions into the local tangent plane of the
canonical ecology cell:

~~~text
canonical cell direction
 -> canonical get_surface_point(direction)
 -> local tangent basis
 -> VIS2 stable record-id jitter
 -> scale by physical neighbor cell spacing
 -> bounded tangent offset
 -> scattered direction
 -> get_surface_point(scattered_direction)
 -> visual PH5 node position
~~~

Two world positions are kept explicitly:

~~~text
base_world
= canonical ecology cell surface point

visual_base_world
= presentation-only scattered surface point
~~~

The old canonical PLAY0/VIS4 getters remain canonical to preserve the accepted
VIS4.4/VIS4.5 contract.

New explicit visual getters expose the presentation position.

## Grid appearance identity

New presentation-only contract:

~~~text
scripts/labs/ecology/eco_evo7_vis4_6_grid_appearance_boundary.gd
~~~

It seals:

~~~text
record_id
cell_index
source_descriptor_hash
cell spacing x/y
jitter fractions x/y
physical visual offsets x/y
appearance_hash
~~~

The contract declares:

~~~text
presentation_only = true
canonical_position = false
ecology_authority = false
network_authority = false
persistence_authority = false
~~~

## Runtime integration

Extended surfaces:

~~~text
scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd
scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd
~~~

The PH5 renderer now keeps canonical and visual position separately.

Node3D translation uses:

~~~text
visual_base_world - render_origin
~~~

while source identity, LOD source position, ecology position and legacy
canonical API remain based on:

~~~text
base_world
~~~

VIS4.5 deterministic orientation remains unchanged:

~~~text
surface-up basis x deterministic local yaw
~~~

VIS4.6 changes translation only.

## Invariants

~~~text
canonical cell_index unchanged
canonical cell direction unchanged
canonical base_world unchanged

GrowthGraph unchanged
RenderDescription unchanged
PH5 geometry identity unchanged by scatter
VIS4.5 individuality identity unchanged by scatter
ecology_state_hash unchanged

scatter deterministic by record_id
scatter bounded inside accepted VIS2 cell fractions
visual point remains on Earth surface

render-origin changes render coordinates only
LOD changes tier only
color changes material only
~~~

## Focused acceptance

New test:

~~~text
tests/ecology/eco_evo7_vis4_6_grid_appearance_boundary_acceptance.gd
~~~

It proves:

~~~text
accepted 32x32 lattice remains present

exact VIS2 SHA-256 jitter semantics reused
same record_id -> exact replay
different record_id -> different deterministic appearance

x bound <= 0.24 cell
y bound <= 0.15 cell

all live PH5 records have appearance_hash
canonical position == get_surface_point(cell direction)
visual position is distinct for live records
visual position is reprojected through get_surface_point(scattered direction)

actual PH5 Node3D translation uses visual position

color switching preserves grid appearance identity
render-origin preserves canonical + visual world positions
LOD preserves canonical + visual positions and appearance hash
ecology_state_hash remains unchanged
~~~

Source guards also require:

~~~text
no process RNG
no biology recomputation
no generation authority
no reproduction/mutation/dispersal authority
no persistence/network authority
~~~

## Canonical runners

~~~text
RUN_ECO_EVO7_VIS4_6_TESTS.sh
RUN_ECO_EVO7_VIS4_6_TESTS.ps1
~~~

The canonical chain is:

~~~text
VIS4.5 full predecessor runner
 -> VIS4.4 / VIS4.5 regression chain
 -> VIS4.6 focused acceptance
~~~

Required final marker:

~~~text
ECO.EVO7 VIS4.6 Grid Appearance Boundary candidate: PASS
~~~

One exact Ubuntu double-Godot GREEN on the frozen subject is sufficient for
closure. A separate Windows acceptance gate is not required.


## Exact Ubuntu closure evidence

The frozen executable subject above completed exact Ubuntu double-Godot
verification without modification.

~~~text
HEAD: 8edc9b9767e8d163b020ac9c7407d385d99bed3b
TREE: 5493dca15e47c23ca939403a98244fd345b37e8b
Godot: 4.7.1.stable.double.custom_build.a13da4feb

VIS4.5 predecessor: PASS
VIS4.6 focused: PASS / 796 assertions
VIS4.6 final marker: PRESENT
canonical runner exit: 0
HEAD/TREE unchanged
tracked worktree clean
~~~

Durable closure checkpoint:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_6_GRID_APPEARANCE_BOUNDARY_UBUNTU_VERIFIED_CLOSED_R1_RU.md
~~~

Final status:

~~~text
VIS4.6 CLOSED
VIS4.7 MORPHOLOGY INSPECTOR UNBLOCKED
~~~
