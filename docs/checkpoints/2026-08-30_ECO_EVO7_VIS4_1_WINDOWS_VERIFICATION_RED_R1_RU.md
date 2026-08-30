# ECO.EVO7 VIS4.1 — Windows Verification RED R1

Дата: 2026-08-30  
Статус: VERIFIED RED / FIX REQUIRED  
Target SHA: 782ceb53d4bd2cf35dd2664d5c05928322b1306c  
TREE: 0ba04b589daaf12b1328741ee82d9ce2b08e1042  
Godot: 4.7.1.stable.double.custom_build.a13da4feb  
Worktree: C:\distributed-world-simulator\eco-vis4-1-verify

## Итог

VIS4.1 R1 не принят.

Exact Windows verifier получил:

~~~text
VIS4.1 full runner: FAIL RC=1
VIS4.1 focused: FAIL RC=1
LS3.4 regression: PASS 45
LS3.6 regression: PASS 114
VIS1/VIS2 regression: PASS 41 + 69
~~~

Focused acceptance:

~~~text
121 assertions
71 failures
~~~

## VIS4.1-WIN-001 — seed identity conflation

R1 evidence contract ошибочно требовал:

~~~text
bundle.individual_seed
==
ph2.individual_seed
==
functional_phenotype.individual_seed
~~~

Но accepted development contract использует два разных deterministic seed domains.

Hereditary bundle seed создаётся mutation/lineage layer и входит в bundle checksum.

LS3.4 затем создаёт отдельный SeedGenomeEnvelope:

~~~text
Contract.create_seed_envelope(
    genome,
    dev_traits,
    lineage_id,
    "ls34-phenotype|<bundle seed>|<bundle checksum prefix>",
    0,
    1.25
)
~~~

SeedEnvelope снова вызывает derive_individual_seed(...), поэтому его individual_seed является development/evaluation seed.

Именно development seed используется PH2 и GrowthGraphSkeleton для:

~~~text
branch presence
branch azimuth
branch angle jitter
branch length jitter
~~~

Следовательно эти identity нельзя отождествлять.

Наблюдение verifier:

~~~text
seed_match ph2=false
seed_match fp=false
build_record_empty=true
~~~

Результат R1:

~~~text
61 living plants
0 evidence records
~~~

Sidecar был запечатан как внутренне валидный empty envelope, после чего Workbench правильно отвергал его как не соответствующий living population.

## VIS4.1-WIN-002 — acceptance runtime abort

R1 acceptance обращался к:

~~~text
result["descriptors"]
~~~

без guard после adapter.build() == {}.

Это породило runtime error и не позволило выполнить поздние tamper checks.

R2 обязан:
- никогда не индексировать failed result без guard;
- продолжать source-level checks;
- делать deterministic checks только на non-empty evidence/adapter.

## VIS4.1-WIN-003 — vacuous determinism

R1 сравнивал hashes двух empty envelopes/adapters.

Такой PASS не является доказательством deterministic morphology.

R2 обязан сначала доказать:

~~~text
living_count > 0
evidence.record_count == living_count
evidence.record_count > 0
adapter.descriptor_count == living_count
~~~

и только затем сравнивать evidence_hash / adapter_hash replay.

## Architecture status R1

Несмотря на RED, verifier подтвердил:

~~~text
single PH2 realization: PASS
single FunctionalPhenotype compile: PASS
presentation cannot abort ecology: PASS
LS3.4 state hash formula unchanged: PASS
LS3.4 evaluation hash formula unchanged: PASS
Descriptor V2 read-only: PASS
generation-zero honesty: PASS
~~~

Это означает, что repair должен быть узким contract repair без изменения biology.

## R2 repair direction

Правильный contract:

~~~text
hereditary_individual_seed
    = hereditary bundle identity

development_individual_seed
    = SeedEnvelope / PH2 / GrowthGraph / FunctionalPhenotype identity
~~~

Оба должны публиковаться явно.

Дополнительно complete sidecar seal должен требовать:

~~~text
evidence record count
==
postcompetition survivor count
~~~

чтобы неполный evidence snapshot не мог выглядеть как валидный presentation snapshot.

Formal acceptance запрещён до fresh exact Windows GREEN R2.
