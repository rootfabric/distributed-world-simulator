# ECO.EVO7 VIS4.8 — Diversity Evidence Ubuntu Exact-Source Verified / CLOSED

Дата: 2026-08-31

Статус:

~~~text
VIS4.8
UBUNTU EXACT-SOURCE DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Canonical executable subject

~~~text
HEAD:
32d9401d2ae7beb2a222b926f07ba44ec50dfe40

TREE:
09feb0705f2ae32f50d5e0e32db048648600e10f
~~~

## Verification provenance

The local Ubuntu environment did not contain a DWS checkout. To preserve the
frozen executable identity without modifying the VIS4 morphology branch, a
temporary validation-only GitHub workflow exported the immutable subject.

Temporary validation PR:

~~~text
#393
Validation only: export exact VIS4.8 source
CLOSED WITHOUT MERGE
~~~

Source-export workflow run:

~~~text
33371467885
SUCCESS
~~~

Before archive creation the workflow independently asserted:

~~~text
git rev-parse HEAD
==
32d9401d2ae7beb2a222b926f07ba44ec50dfe40

git rev-parse HEAD^{tree}
==
09feb0705f2ae32f50d5e0e32db048648600e10f
~~~

The exact commit was exported through git archive.

The downloaded archive was then reconstructed in the local Ubuntu environment.
Independent git write-tree output was:

~~~text
09feb0705f2ae32f50d5e0e32db048648600e10f
~~~

which exactly matches the canonical frozen TREE.

Therefore the locally executed source tree is byte-identical to the canonical
VIS4.8 executable tree.

## Attached Godot identity

Verification used the Godot archive attached to the project:

~~~text
godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz
~~~

Extracted binary identity:

~~~text
version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

This is the canonical double-precision Godot build.

## Canonical runner

Executed:

~~~text
RUN_ECO_EVO7_VIS4_8_TESTS.sh
~~~

Result:

~~~text
RUNNER_RC=0
~~~

## Full predecessor chain

The complete transitive chain remained GREEN:

~~~text
FFF2 Morphology Evolution                 PASS / 56
PH2 Environment-Coupled Development      PASS / 107
VIS4.0 Truth / Contract Audit            PASS / 176
LS3.4 Local Competition                  PASS / 45
LS3.6 Rule Workbench                     PASS / 114
VIS4.1 Descriptor V2                     PASS / 598
VIS1                                     PASS / 41
VIS2                                     PASS / 69
VIS3                                     PASS / 107
VIS4.2 Honest Diagnostic Morphology      PASS / 1265
PH5                                      PASS / 720
PH5-S2                                   PASS / 387
PH5-S3                                   PASS / 49
PH5-S3 materialization                   PASS / 61
PH5-S4 robustness                        PASS / 5026
PH5-S4 matrix                            PASS / 430
VIS4.3 Exact Live Phenotype -> PH5       PASS / 752
PLAY0 Live Planet Playground             PASS / 103
VIS4.4 PLAY0.MORPH                       PASS / 74
VIS4.5 Deterministic Individuality       PASS / 491
VIS4.6 Grid Appearance Boundary          PASS / 796
VIS4.7 Morphology Inspector              PASS / 106
VIS4.8 Diversity Evidence                PASS / 106
~~~

## VIS4.8 independent gates

The focused stage reported both gates separately.

Renderer fidelity:

~~~text
VIS4.8 RENDERER FIDELITY: PASS
~~~

The controlled acceptance proved non-vacuous presentation differences for:

~~~text
tall / low
narrow / wide
vertical / bushy
structurally sparse / dense
different branch angles
realized crown-density visual cue
~~~

Live population diversity:

~~~text
VIS4.8 LIVE DIVERSITY:
LIVE_DIVERSITY_SUFFICIENT
~~~

This is stronger than merely proving that the renderer can express diversity:
the actually published generation-one population crossed the accepted R1
morphology evidence thresholds.

## Anti-cheat evidence

The controlled collapsed-population fixture verified:

~~~text
8 distinct lineages
8 distinct descriptor identities
8 distinct render-description identities
identical morphology

-> cluster_count = 1
-> varying_field_count = 0
-> LIVE_DIVERSITY_INSUFFICIENT
~~~

Therefore lineage, render identity, seed, VIS4.5 yaw and VIS4.6 visual scatter do
not masquerade as morphology diversity.

The controlled truly diverse morphology fixture independently crossed the
cluster/varying-field thresholds and returned:

~~~text
LIVE_DIVERSITY_SUFFICIENT
~~~

## Live evidence contract

The live report is sealed to:

~~~text
ecology_state_hash
Descriptor V2 adapter_hash
source_competition_hash
source_morphology_evidence_hash
~~~

Per-record binding additionally requires:

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

The live diversity vector counts only morphology fields.

Explicit exclusions remain:

~~~text
lineage_counts_as_morphology = false
seed_counts_as_morphology = false
yaw_counts_as_morphology = false
scatter_counts_as_morphology = false
archetype_classification = false
~~~

No TREE/BUSH/GRASS taxonomy or random decoration was introduced.

## Non-causal invariants

VIS4.8 evidence operations preserved:

~~~text
ecology_state_hash
PH5 geometry identity
VIS4.5 individuality identity
VIS4.6 grid appearance identity
~~~

The VIS4.8 live runtime adds no:

~~~text
process RNG
GrowthGraph build
FunctionalPhenotype recomputation
CoupledDevelopment recomputation
generation mutation
reproduction authority
mutation authority
dispersal authority
persistence authority
network authority
~~~

Controlled GrowthGraph use remains acceptance-fixture-only for renderer fidelity.

## Fresh import note

Fresh import emitted only the already-known ancestor scene diagnostics in:

~~~text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
~~~

They were non-fatal, remained outside the current VIS4 execution path, and the
full canonical chain subsequently completed GREEN.

No new VIS4.8 parse/load/runtime failure occurred.

## Post-run exactness

After the canonical runner:

~~~text
TREE:
09feb0705f2ae32f50d5e0e32db048648600e10f

TREE unchanged:
YES

tracked status:
clean
~~~

Full local verification log SHA-256:

~~~text
06a76ce32c201c510238a2bf220b2467db9fa35b56a3211eb896a082b6616e13
~~~

## Closure

Canonical VIS4.8 executable boundary remains:

~~~text
HEAD:
32d9401d2ae7beb2a222b926f07ba44ec50dfe40

TREE:
09feb0705f2ae32f50d5e0e32db048648600e10f
~~~

Final qualification:

~~~text
VIS4.8 UBUNTU EXACT-SOURCE GREEN
CANONICAL HEAD VERIFIED
CANONICAL TREE VERIFIED
LOCAL TREE RECONSTRUCTION EXACT
ATTACHED DOUBLE GODOT VERIFIED
VIS4.7 PREDECESSOR GREEN

RENDERER FIDELITY PASS
LIVE_DIVERSITY_SUFFICIENT

VIS4.8 FOCUSED PASS / 106
RUNNER RC=0
TRACKED TREE CLEAN

VIS4.8 CLOSED
VIS4.9 PERFORMANCE / LOD UNBLOCKED
~~~

A separate Windows acceptance gate is not required for this checkpoint.
