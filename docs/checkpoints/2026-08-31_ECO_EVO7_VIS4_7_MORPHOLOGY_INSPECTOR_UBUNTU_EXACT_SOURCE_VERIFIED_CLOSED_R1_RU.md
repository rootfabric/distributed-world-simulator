# ECO.EVO7 VIS4.7 — Morphology Inspector Ubuntu Exact-Source Verified / CLOSED

Дата: 2026-08-31

Статус:

~~~text
VIS4.7
UBUNTU EXACT-SOURCE DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Canonical executable subject

~~~text
HEAD:
7b3479156a6920083f6cc2c420fcb21834e6dc5e

TREE:
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

## Verification provenance

Local execution environment did not contain a DWS checkout and outbound git
network access was unavailable.

To preserve exact-subject verification without modifying the VIS4.7 branch, a
temporary validation-only GitHub workflow exported the immutable subject.

Temporary validation PR:

~~~text
#385
Validation only: export exact VIS4.7 source
CLOSED WITHOUT MERGE
~~~

Source-export workflow run:

~~~text
run:
33367245920

result:
SUCCESS
~~~

Before archive creation the GitHub runner independently asserted:

~~~text
git rev-parse HEAD
==
7b3479156a6920083f6cc2c420fcb21834e6dc5e

git rev-parse HEAD^{tree}
==
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

The exact commit was then exported using `git archive`.

After download into the Ubuntu execution environment, the extracted archive was
reconstructed into a temporary Git index and independently produced:

~~~text
git write-tree
==
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

Therefore the locally executed source tree is byte-identical to the canonical
VIS4.7 TREE.

Qualification note:

~~~text
local checkout form:
exact reconstructed TREE from immutable git archive

not:
literal detached checkout containing original commit object

canonical HEAD identity:
independently asserted by GitHub before archive export
~~~

This provenance chain is accepted for VIS4.7 closure because both canonical
HEAD and canonical TREE were independently sealed before local execution, and
the locally executed tree exactly reconstructed the canonical TREE.

## Godot identity

~~~text
version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

Both version and SHA-256 were checked in the local Ubuntu execution environment.

## Canonical runner

Executed:

~~~text
RUN_ECO_EVO7_VIS4_7_TESTS.sh
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
~~~

## VIS4.7 focused result

~~~text
ECO.EVO7 VIS4.7 Morphology Inspector: PASS (106 assertions)
~~~

Final canonical marker:

~~~text
ECO.EVO7 VIS4.7 Morphology Inspector candidate: PASS
~~~

## Verified VIS4.7 behavior

Focused acceptance proved:

~~~text
generation zero:
no fabricated phenotype
explicit unavailable evidence boundary

F6-equivalent open:
exact nearest currently materialized PH5 plant selected

selected record:
record_id exact
cell_index exact
lineage exact
hereditary seed exact
development seed exact

Descriptor V2:
descriptor hash exact
phenotype hash exact
GrowthGraph hash exact

genetic potential:
exact pass-through

realized topology:
exact pass-through

functional morphology:
exact pass-through

competition context:
water/light/resource exact pass-through

VIS4.5:
individuality identity exact
deterministic yaw exact

PH5:
render description exact
representation exact
materialization exact
current tier exact

VIS4.6:
appearance hash exact
canonical world position exact
visual world position exact
visual offset explicitly NONCANONICAL
~~~

The human-visible panel exposes required morphology/resource sections and full
64-character source/render seals.

## Fail-closed behavior

Verified:

~~~text
invalid negative selection:
REJECT

out-of-range selection:
REJECT

last valid inspector state:
PRESERVED

tampered descriptor/render binding:
REJECT

tampered descriptor/grid-appearance binding:
REJECT
~~~

## Non-causal invariants

Opening, selecting and closing the inspector preserved:

~~~text
ecology_state_hash
PH5 geometry identity
VIS4.5 individuality identity
VIS4.6 grid appearance identity
~~~

The inspector remains a read-only presentation surface.

## Authority result

VIS4.7 adds no:

~~~text
GrowthGraph build
FunctionalPhenotype recomputation
CoupledDevelopment recomputation
reproduction authority
mutation authority
dispersal authority
persistence authority
network authority
~~~

## Fresh import note

Fresh Godot import emitted the already-known ancestor scene parse diagnostics in:

~~~text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
~~~

These diagnostics were non-fatal, are outside the VIS4.7 execution path, and
the complete canonical runner subsequently completed GREEN.

No new VIS4.7 parse/load/runtime error occurred.

## Post-run exactness

After the canonical runner:

~~~text
reconstructed TREE:
8fedc29f3837f632d5c264080e8d5897beae1861

tracked status:
clean
~~~

Full local log SHA-256:

~~~text
582cb93f142c76b49fe4f936b12ec88ece9ccbc6e2283b65a3c090378cc9e5fd
~~~

## Closure

Canonical VIS4.7 executable boundary remains:

~~~text
HEAD:
7b3479156a6920083f6cc2c420fcb21834e6dc5e

TREE:
8fedc29f3837f632d5c264080e8d5897beae1861
~~~

Final qualification:

~~~text
VIS4.7 UBUNTU EXACT-SOURCE GREEN
CANONICAL HEAD VERIFIED BEFORE ARCHIVE
CANONICAL TREE VERIFIED BEFORE ARCHIVE
LOCAL TREE RECONSTRUCTION EXACT
DOUBLE GODOT VERIFIED
VIS4.6 PREDECESSOR GREEN
VIS4.7 MORPHOLOGY INSPECTOR GREEN
TRACKED TREE CLEAN

VIS4.7 CLOSED
VIS4.8 DIVERSITY EVIDENCE UNBLOCKED
~~~

A separate Windows acceptance gate is not required for this checkpoint.
