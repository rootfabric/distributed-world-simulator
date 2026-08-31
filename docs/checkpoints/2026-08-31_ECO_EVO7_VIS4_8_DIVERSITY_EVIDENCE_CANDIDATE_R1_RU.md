# ECO.EVO7 VIS4.8 — Diversity Evidence R1 Candidate

Дата: 2026-08-31

Статус:

~~~text
VIS4.8 IMPLEMENTED CANDIDATE
EXACT UBUNTU DOUBLE-GODOT VERIFICATION REQUIRED
NOT CLOSED
~~~

## Frozen executable subject

~~~text
HEAD:
32d9401d2ae7beb2a222b926f07ba44ec50dfe40

TREE:
09feb0705f2ae32f50d5e0e32db048648600e10f
~~~

Predecessor:

~~~text
VIS4.7 CLOSED

canonical executable:
7b3479156a6920083f6cc2c420fcb21834e6dc5e
~~~

## Goal

VIS4.8 makes diversity evidence explicit and separates two independent questions:

~~~text
1. RENDERER FIDELITY
Can the accepted presentation stack visibly represent controlled morphology differences?

2. LIVE DIVERSITY
Does the currently published real population actually contain quantitative morphology diversity?
~~~

These gates must never be conflated.

A valid VIS4.8 result may therefore be:

~~~text
RENDERER_PASS
LIVE_DIVERSITY_INSUFFICIENT
~~~

This is an honest result, not an acceptance failure of the evidence system.

VIS4.8 must never synthesize random TREE/BUSH/GRASS forms to hide a collapsed
live population.

## New live diversity model

New read-only module:

~~~text
scripts/labs/ecology/eco_evo7_vis4_8_diversity_evidence.gd
~~~

It consumes only:

~~~text
completed generation
source ecology_state_hash
VIS4.1 Descriptor V2 snapshot
PH5 render identities
~~~

It performs no biology computation.

Source provenance is sealed to:

~~~text
source_ecology_hash
Descriptor V2 adapter_hash
source_competition_hash
source_morphology_evidence_hash
~~~

Every record additionally requires exact binding:

~~~text
descriptor.record_id
==
render_identity.record_id

descriptor.descriptor_hash
==
render_identity.source_descriptor_hash

descriptor.growth_graph_hash
==
render_identity.source_growth_graph_hash
~~~

## Morphology-only live metrics

The live gate intentionally excludes lineage, seed, yaw and VIS4.6 scatter.

Fixed morphology metrics:

~~~text
functional morphology:
  realized_height_m
  realized_crown_radius_m
  realized_crown_density
  leaf_area_index_proxy
  structural_investment
  realized_root_depth_m
  realized_root_spread_m

realized topology:
  apical_dominance
  branch_probability
  branch_angle_deg
  branch_length_ratio
  branching_depth
  crown_spread_m

potential morphology:
  foliage_density
~~~

For every metric VIS4.8 reports:

~~~text
mean
population variance
standard deviation
min
max
range
relative spread
fixed evidence bin
varying / flat
~~~

## Morphology clusters

Clusters are deterministic quantized morphology signatures.

They are not taxa.

No canonical morphology class is created.

~~~text
record morphology vector
 -> fixed per-field evidence bins
 -> quantized vector
 -> SHA-256 cluster signature
~~~

The histogram is deterministic and sorted by signature.

Explicit contract:

~~~text
archetype_classification = false

lineage_counts_as_morphology = false
seed_counts_as_morphology = false
yaw_counts_as_morphology = false
scatter_counts_as_morphology = false
~~~

Therefore different lineage colors, different VIS4.5 yaw or different VIS4.6
scatter cannot falsely increase morphology diversity.

## Live qualification thresholds

R1 fixes presentation-evidence thresholds:

~~~text
MIN_POPULATION        = 8
MIN_CLUSTER_COUNT     = 3
MIN_VARYING_FIELDS    = 4
MIN_RELATIVE_SPREAD   = 0.05
~~~

A field is varying only if it crosses both:

~~~text
range >= fixed evidence bin
relative_spread >= 0.05
~~~

The live status is derived only from evidence:

~~~text
population >= 8
AND
cluster_count >= 3
AND
varying_field_count >= 4

-> LIVE_DIVERSITY_SUFFICIENT

otherwise

-> LIVE_DIVERSITY_INSUFFICIENT
~~~

validate() independently recomputes cluster counts, histogram population,
varying-field count and expected live status. A caller cannot relabel an
insufficient report as sufficient without invalidating the evidence hash.

## Diagnostic identity counts

VIS4.8 also reports:

~~~text
unique descriptor count
unique GrowthGraph count
unique render-description count
lineage count
~~~

These are diagnostic only.

They do not contribute to morphology sufficiency.

## F7 PLAY0 evidence panel

PLAY0 now exposes:

~~~text
F7
 -> VIS4.8 Diversity Evidence
~~~

New APIs:

~~~text
is_diversity_evidence_visible()
get_diversity_evidence_state()
get_diversity_evidence_text()
set_diversity_evidence_visible()
toggle_diversity_evidence()
~~~

The F7 panel shows:

~~~text
generation
population
live diversity status
cluster count
varying field count
descriptor / GrowthGraph / render-description identity counts
lineage count as diagnostic-only
per-field morphology variance/range
full evidence_hash
explicit NO TREE/BUSH/GRASS ARCHETYPES notice
~~~

Generation zero produces no diversity report and explicitly reports that a
completed generation > 0 source is unavailable.

F6 Morphology Inspector and F7 Diversity Evidence share one diagnostic HUD slot
and are mutually exclusive visually.

Switching panels does not change either evidence state.

## Controlled renderer fidelity gate

Focused acceptance uses the accepted PH5 core directly:

~~~text
PlantDevelopmentTraits
 -> PlantGrowthGraphSkeleton
 -> PlantRenderDescription
~~~

with a fixed individual seed.

Controlled probes require:

~~~text
tall vs low
 -> different rendered bounds height
 -> different render description

narrow vs wide
 -> different horizontal crown extent
 -> different render description

vertical vs bushy
 -> different lateral branch population
 -> different structural foliage population

sparse vs dense
 -> different branch primitive population
 -> different foliage anchor population

low vs high branch angle
 -> different actual mean lateral angle
 -> different render description
~~~

The already accepted VIS4.2 diagnostic density cue is also checked:

~~~text
low realized_crown_density
vs
high realized_crown_density

-> different visual alpha
-> different foliage cluster count
~~~

This keeps renderer fidelity evidence non-vacuous without inventing a second
renderer.

## Anti-cheat controlled diversity fixture

Acceptance contains a deliberately collapsed population:

~~~text
8 records
8 distinct lineages
8 distinct descriptor identities
8 distinct render-description identities

BUT

identical morphology vectors
~~~

Required result:

~~~text
cluster_count = 1
varying_field_count = 0
LIVE_DIVERSITY_INSUFFICIENT
~~~

This proves lineage/identity variation cannot masquerade as morphology diversity.

A second controlled population varies real morphology fields and must cross the
R1 cluster/varying-field thresholds, yielding:

~~~text
LIVE_DIVERSITY_SUFFICIENT
~~~

## Non-causal invariants

Opening, closing or recomputing VIS4.8 evidence must preserve:

~~~text
ecology_state_hash
PH5 geometry identity
VIS4.5 individuality identity
VIS4.6 grid appearance identity
~~~

VIS4.8 runtime contains no:

~~~text
process RNG
GrowthGraph.build
FunctionalPhenotype recomputation
CoupledDevelopment recomputation
generation mutation
reproduction/mutation/dispersal authority
persistence authority
network authority
~~~

The PH5 GrowthGraph calls used by the focused test exist only in controlled
renderer-fidelity fixtures, never in the live VIS4.8 runtime path.

## Focused acceptance

New acceptance:

~~~text
tests/ecology/eco_evo7_vis4_8_diversity_evidence_acceptance.gd
~~~

It proves:

~~~text
controlled PH5 renderer fidelity
controlled realized crown-density cue
collapsed anti-cheat population -> INSUFFICIENT
controlled real morphology diversity -> SUFFICIENT

generation-zero no-fabrication
live exact Descriptor V2 + PH5 binding
live deterministic report replay
variance replay exact
cluster histogram replay exact

F7 panel content
F6/F7 mutual exclusion
source tamper rejection

ecology identity unchanged
geometry identity unchanged
individuality identity unchanged
grid appearance identity unchanged
~~~

The focused test prints two independent result lines:

~~~text
VIS4.8 RENDERER FIDELITY: PASS
VIS4.8 LIVE DIVERSITY: <LIVE_DIVERSITY_SUFFICIENT | LIVE_DIVERSITY_INSUFFICIENT>
~~~

The final acceptance marker remains GREEN if the evidence system is correct,
even when the real live population reports LIVE_DIVERSITY_INSUFFICIENT.

## Canonical runners

~~~text
RUN_ECO_EVO7_VIS4_8_TESTS.sh
RUN_ECO_EVO7_VIS4_8_TESTS.ps1
~~~

Canonical chain:

~~~text
VIS4.7 full predecessor runner
 -> VIS4.5 / VIS4.6 / VIS4.7 regressions
 -> VIS4.8 focused diversity evidence
~~~

Required final marker:

~~~text
ECO.EVO7 VIS4.8 Diversity Evidence candidate: PASS
~~~

One exact Ubuntu double-Godot GREEN on the frozen subject is sufficient for
closure. A separate Windows acceptance gate is not required.
