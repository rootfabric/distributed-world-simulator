# ECO.EVO7 VIS4.1 R2 — Windows Verified / Closed

Дата closure: 2026-08-31  
Статус: ACCEPTED / WINDOWS VERIFIED / CLOSED  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1

## Exact-tested implementation subject

~~~text
HEAD:
c499a39ee3fa4c7b5ab871df7f89f7cb4b6ec436

TREE:
4427bada5367f9b06d4b642a6ab9e73670821c2e

Godot:
4.7.1.stable.double.custom_build.a13da4feb
~~~

Fresh detached verification worktree:

~~~text
C:\distributed-world-simulator\eco-vis4-1-r2-verify
~~~

Tracked tree после тестов: clean.

Godot import создал 109 untracked `.gd.uid` sidecar artifacts. Они существовали до и после decisive run, не были добавлены в Git и не меняют tested tree identity.

## Predecessor RED

R1 exact subject:

~~~text
782ceb53d4bd2cf35dd2664d5c05928322b1306c
~~~

R1 был корректно отклонён fresh Windows verifier из-за conflation:

~~~text
hereditary bundle individual_seed
==
PH2 / development individual_seed
~~~

Repair R2 разделил эти domains на:

~~~text
hereditary_individual_seed
development_individual_seed
~~~

R1 RED history остаётся сохранённой в:

~~~text
docs/checkpoints/2026-08-30_ECO_EVO7_VIS4_1_WINDOWS_VERIFICATION_RED_R1_RU.md
~~~

Repair rationale:

~~~text
docs/checkpoints/2026-08-30_ECO_EVO7_VIS4_1_SEED_IDENTITY_REPAIR_R2_RU.md
~~~

## Decisive Windows verification

Canonical invocation был выполнен без Tee-Object / stderr-rewrapping.

Результат:

~~~text
VIS4.0 Truth / Contract Audit: PASS (176 assertions)

FFF2 parent chain:
FFF2:   PASS 56
FFF1:   PASS 110
FFF0:   PASS 112
P1B-S1: PASS 5834
PH2:    PASS 107
P1A-S1: PASS 109
P1A-S2: PASS 235
P1C-S4: PASS 15
PH0:    PASS 63

LS3.4: PASS (45 assertions)
LS3.6: PASS (114 assertions)

VIS4.1 R2 focused:
PASS (598 assertions)

VIS1: PASS (41 assertions)
VIS2: PASS (69 assertions)

full runner: PASS
runner RC: 0
~~~

Final runner line:

~~~text
ECO.EVO7 VIS4.1 R2 Source-Bound Morphology Evidence candidate: PASS
~~~

## Non-vacuous morphology evidence

Generation-one live fixture:

~~~text
living plants: 61
evidence records: 61
Descriptor V2 records: 61
morphology_evidence_count: 61
founder_marker_count: 0
~~~

Therefore R2 evidence is explicitly non-vacuous:

~~~text
evidence.record_count > 0

evidence.record_count
==
live record_count
==
descriptor_count
==
morphology_evidence_count
~~~

The R1 failure mode `0 evidence == 0 evidence` cannot satisfy R2 acceptance.

## Seed identity closure

For all 61/61 living records:

~~~text
evidence.hereditary_individual_seed
==
hereditary_bundle.individual_seed
~~~

Development identity is independently sealed by:

~~~text
development_individual_seed
==
PH2.individual_seed
==
GrowthGraph.individual_seed
==
FunctionalPhenotype.individual_seed
~~~

The live fixture observed:

~~~text
hereditary_individual_seed
!=
development_individual_seed
~~~

for 61/61 records.

Thus the two seed domains are proven distinct by runtime evidence, not only by source inspection.

## Tamper closure

All tamper assertions executed in the same PASS run.

### Morphology value tamper

~~~text
changed morphology value + stale hash
-> MorphologyEvidence reject
-> Descriptor V2 reject
~~~

### Wrong population rehash

~~~text
internally rehashed standalone evidence
+
wrong postcompetition population binding
-> Workbench reject
-> Descriptor V2 reject
~~~

### Competition seal

~~~text
forged competition field_hash
-> Descriptor V2 reject
~~~

### Hereditary seed rehash

~~~text
changed hereditary_individual_seed
+
rehashed evidence record
+
rehashed evidence snapshot
-> standalone evidence internally self-consistent
-> Workbench rejects against live hereditary bundle
-> Descriptor V2 rejects against live hereditary bundle
~~~

This proves source binding survives an attacker/reproducer recomputing presentation hashes.

## Determinism closure

Both reference and replay produced non-empty evidence and non-empty descriptors.

~~~text
ecology_state_hash A == ecology_state_hash B
morphology_evidence_hash A == morphology_evidence_hash B
adapter_hash A == adapter_hash B
~~~

Observed fixture hashes:

~~~text
ecology_state_hash:
33747a40b3676acc1add0d58bf866f2f4e2cb2798da366f6e79ff41cdd5f2fe5

evidence_hash:
03a2ffe7adc23b6cd059b03a0668f4c7550c800b22a118886d0ed8160d92f59f

adapter_hash:
850a4f4a9492a6a6c8db614094ce46cebfb8a63e4e35cc4ddc5babed9031e80a
~~~

These hashes are evidence for this exact fixture and exact tested subject, not new canonical ecology identifiers.

## Authority closure

Verified GREEN:

~~~text
single PH2 realization call site
single FunctionalPhenotype compile call site
no renderer-side biology recomputation

evidence failure cannot abort ecology generation
presentation_only = true
derived_representation = true

no mutation/reproduction/dispersal authority
no persistence/network authority

ecology state_hash remains outside morphology evidence
evaluation seal remains source-owned by LS3.4
~~~

VIS4.1 therefore remains a reconstructable, source-bound, read-only presentation layer.

## Formal verdict

~~~text
ECO.EVO7 VIS4.1 R2
WINDOWS VERIFICATION: PASS

VIS4.1:
ACCEPTED
WINDOWS VERIFIED
CLOSED
~~~

The exact-tested executable/code boundary is:

~~~text
c499a39ee3fa4c7b5ab871df7f89f7cb4b6ec436
TREE 4427bada5367f9b06d4b642a6ab9e73670821c2e
~~~

Documentation commits after this SHA do not alter the tested implementation subject.

## Next

Canonical next checkpoint:

~~~text
VIS4.2 — Honest Diagnostic Morphology
~~~

VIS4.2 must:
- consume Descriptor V2 only;
- not call CoupledDevelopment or FunctionalPhenotype;
- map realized crown radius/density and realized topology into diagnostic shape;
- include neutral-color shape evidence;
- preserve ecology state_hash;
- remain diagnostic presentation, not yet replace primary PLAY0 renderer.

VIS4.3 remains the later PH5 bridge.  
VIS4.4 remains PLAY0.MORPH.
