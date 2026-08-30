# ECO.EVO7 VIS4.1 R2 — Seed Identity Repair Candidate

Дата: 2026-08-30  
Статус: IMPLEMENTED REPAIR CANDIDATE / NOT ACCEPTED  
Predecessor RED: VIS4.1-WIN-001..003  
Repair base: 782ceb53d4bd2cf35dd2664d5c05928322b1306c

## Решение

R2 не меняет accepted biology.

Он исправляет только derived presentation contract.

### Seed domains

~~~text
hereditary_individual_seed
    |
    +-- source: hereditary_bundle.individual_seed
    +-- participates in bundle_checksum
    +-- stable hereditary/reproduction identity

development_individual_seed
    |
    +-- source: SeedGenomeEnvelope.individual_seed
    +-- consumed by PH2
    +-- consumed by GrowthGraphSkeleton
    +-- copied into FunctionalPhenotype
    +-- controls exact realized branching stochastic geometry
~~~

R2 запрещает сравнивать эти два seed как одну identity.

Вместо этого проверяется:

~~~text
development_individual_seed
==
PH2.individual_seed
==
GrowthGraph.individual_seed
==
FunctionalPhenotype.individual_seed
~~~

а hereditary seed независимо связывается с live hereditary bundle.

## Complete sidecar seal

PlantMorphologyEvidence.seal_snapshot() теперь принимает expected survivor record count.

~~~text
records.size()
!=
expected_postcompetition_record_count
        ->
return {}
~~~

Это не влияет на ecology generation.

При incomplete evidence:

~~~text
ecology generation succeeds
morphology sidecar unavailable
presentation fail-closed
~~~

## Stronger source binding

Workbench и Descriptor V2 дополнительно проверяют:

~~~text
evidence.lineage_id
==
live bundle lineage_id

evidence.hereditary_individual_seed
==
live bundle individual_seed
~~~

Descriptor V2 также сверяет potential_morphology с raw hereditary source fields.

## Acceptance hardening

R2 focused acceptance:
- guard-ит каждый failed dictionary before indexing;
- требует non-empty generation-one living population;
- требует evidence_count == living_count;
- требует evidence_count > 0;
- требует descriptor_count == living_count;
- проверяет оба seed domains;
- требует fixture evidence, где два seed domains фактически различаются;
- deterministic replay сравнивается только между двумя non-empty sidecars/adapters;
- tamper suite выполняется отдельно;
- добавлен rehashed hereditary-seed tamper: standalone evidence internally consistent, но Workbench/Descriptor обязаны reject по live bundle binding.

## Authority

Не изменены:
- mutation authority;
- development biology;
- competition;
- population identity;
- ecology state_hash;
- evaluation_hash;
- persistence/network authority.

## Exit

R2 остаётся candidate до fresh exact Windows verification:

~~~text
full runner RC=0
focused R2 RC=0
LS3.4 GREEN
LS3.6 GREEN
VIS1/VIS2 GREEN
non-vacuous deterministic evidence GREEN
clean tracked worktree
~~~
