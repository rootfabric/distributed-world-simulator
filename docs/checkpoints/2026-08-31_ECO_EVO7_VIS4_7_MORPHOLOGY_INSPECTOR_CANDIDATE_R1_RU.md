# ECO.EVO7 VIS4.7 — Morphology Inspector R1 Candidate

Дата: 2026-08-31

Статус:

~~~text
VIS4.7 R1
UBUNTU EXACT-SOURCE DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Frozen executable subject

~~~text
HEAD:
7b3479156a6920083f6cc2c420fcb21834e6dc5e

TREE:
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

Predecessor:

~~~text
VIS4.6 CLOSED
canonical executable:
8edc9b9767e8d163b020ac9c7407d385d99bed3b
~~~

## Goal

VIS4.7 adds a read-only in-world morphology inspector to PLAY0.

Human interaction:

~~~text
F6
 -> open morphology inspector
 -> select nearest currently materialized PH5 plant
 -> display exact source-bound morphology + presentation identity
~~~

The inspector is not a simulation component and introduces no biology,
selection, mutation, persistence or network authority.

## Source chain

~~~text
completed PLAY0 generation
 -> VIS4.1 Descriptor V2
 -> exact PH5 render identity
 -> VIS4.5 individuality identity
 -> VIS4.6 grid appearance identity
 -> VIS4.7 read-only InspectorModel
 -> HUD text
~~~

The model accepts a record only when:

~~~text
descriptor.record_id == render_identity.record_id
descriptor.descriptor_hash == render_identity.source_descriptor_hash
descriptor.growth_graph_hash == render_identity.source_growth_graph_hash
descriptor.record_id == grid_appearance.record_id
descriptor.descriptor_hash == grid_appearance.source_descriptor_hash
~~~

PLAY0 additionally requires the morphology snapshot generation and
source_ecology_state_hash to match the currently published completed ecology
snapshot before any inspection is allowed.

## New durable surface

~~~text
scripts/labs/ecology/eco_evo7_vis4_7_morphology_inspector_model.gd
~~~

The model contains only read-side composition and formatting.

It exposes:

~~~text
generation
record_id
cell_index
lineage_id

hereditary_individual_seed
development_individual_seed
orientation_yaw_deg

genetic potential morphology
realized PH2 topology
functional morphology
competition context

current PH5 tier
canonical world position
VIS4.6 visual world position
visual_offset_is_canonical = false

full source/render hashes
inspector_hash
~~~

## Human-visible fields

The F6 panel shows:

~~~text
lineage
generation
record id / cell index
hereditary + development seeds
VIS4.5 deterministic yaw

realized height
realized crown radius
realized crown density
LAI

realized internode length
apical dominance
branch probability
branch angle
branch length ratio
branching depth
crown spread

leaf size
leaf conservative strategy
structural investment

realized root depth
realized root spread
root/shoot ratio

water satisfaction
effective light
realized resource balance

genetic potential:
max height
crown spread
foliage density
internode
apical dominance
branch probability
branch angle
branch length ratio
branching depth
leaf economics
structural investment
root depth/spread
root/shoot

canonical position
VIS4.6 presentation position
NONCANONICAL visual-offset marker
~~~

Full 64-character source/render seals are displayed for:

~~~text
ecology state
descriptor
phenotype
plasticity phenotype
morphology evidence record
competition evaluation
GrowthGraph
VIS4.5 individuality
render description
representation
materialization
VIS4.6 appearance
VIS4.7 inspector
~~~

## PLAY0 behavior

PLAY0 now exposes:

~~~text
set_morphology_inspector_visible()
toggle_morphology_inspector()
select_morphology_inspector_index()

get_morphology_inspector_state()
get_morphology_inspector_text()
get_morphology_inspector_selected_index()
is_morphology_inspector_visible()
~~~

F6 opening semantics:

~~~text
current player/spectator world position
 -> all currently materialized PH5 individuals
 -> exact minimum visual-world distance
 -> selected record
~~~

Each new F6 opening recomputes the nearest record.

If the inspector remains open across a completed generation:

~~~text
same record_id survived
 -> preserve that record

record disappeared
 -> select new nearest materialized PH5 record
~~~

Generation zero does not fabricate phenotype data; the inspector explicitly
reports that completed generation > 0 morphology evidence is unavailable.

The HUD panel is mouse-filter IGNORE and cannot steal gameplay mouse input.

## Non-causal invariant

Opening, closing or selecting inspector records must not change:

~~~text
ecology_state_hash
PH5 geometry identity
VIS4.5 individuality identity
VIS4.6 grid appearance identity
~~~

Invalid record indices fail closed and preserve the last valid inspector state.

Tampered descriptor/render or descriptor/grid bindings are rejected.

## Focused acceptance

New acceptance:

~~~text
tests/ecology/eco_evo7_vis4_7_morphology_inspector_acceptance.gd
~~~

It proves:

~~~text
generation-zero fail-closed/no fabricated phenotype
F6-equivalent live opening
exact nearest materialized PH5 selection

selected record_id/cell/lineage/seeds exact
Descriptor V2 hashes exact
genetic potential exact pass-through
realized topology exact pass-through
functional morphology exact pass-through
water/light/resource exact pass-through

VIS4.5 individuality/render identity exact
VIS4.6 appearance/canonical/visual positions exact

human panel contains required morphology/resource/source sections
full source/render seals exposed

explicit record selection works
invalid selection rejected with last valid state preserved

tampered source bindings rejected

ecology identity unchanged
geometry identity unchanged
individuality identity unchanged
grid appearance identity unchanged
~~~

Source guards require the VIS4.7 model to contain:

~~~text
no GrowthGraph.build
no FunctionalPhenotype recomputation
no CoupledDevelopment recomputation
no reproduction/mutation/dispersal authority
no persistence/network authority
~~~

## Canonical runners

~~~text
RUN_ECO_EVO7_VIS4_7_TESTS.sh
RUN_ECO_EVO7_VIS4_7_TESTS.ps1
~~~

Canonical chain:

~~~text
VIS4.6 full predecessor runner
 -> VIS4.5 / VIS4.6 regressions
 -> VIS4.7 focused morphology inspector acceptance
~~~

Required marker:

~~~text
ECO.EVO7 VIS4.7 Morphology Inspector candidate: PASS
~~~

One exact Ubuntu double-Godot GREEN on the frozen subject is sufficient for
closure. A separate Windows acceptance gate is not required.


## Ubuntu exact-source closure evidence

The frozen executable subject above completed local Ubuntu verification using an
immutable exact source archive exported by a validation-only GitHub workflow.

Before archive creation GitHub independently asserted:

~~~text
HEAD:
7b3479156a6920083f6cc2c420fcb21834e6dc5e

TREE:
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

The downloaded archive reconstructed locally to the same exact TREE:

~~~text
git write-tree:
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

Canonical local execution:

~~~text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

Godot SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

RUN_ECO_EVO7_VIS4_7_TESTS.sh:
RC=0

VIS4.6 predecessor:
PASS / 796 assertions

VIS4.7 focused:
PASS / 106 assertions

VIS4.7 final marker:
PRESENT

tracked reconstructed tree:
clean
~~~

Temporary source-export PR #385 was closed without merge after artifact
retrieval. The VIS4.7 executable branch was never modified by that validation
workflow.

Durable closure checkpoint:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_7_MORPHOLOGY_INSPECTOR_UBUNTU_EXACT_SOURCE_VERIFIED_CLOSED_R1_RU.md
~~~

Final status:

~~~text
VIS4.7 CLOSED
VIS4.8 DIVERSITY EVIDENCE UNBLOCKED
~~~
