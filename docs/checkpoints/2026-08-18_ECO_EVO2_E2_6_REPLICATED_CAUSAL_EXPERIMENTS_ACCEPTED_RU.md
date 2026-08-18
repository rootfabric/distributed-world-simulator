# ECO.EVO2 / E2.6 Replicated Causal Experiments — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Scope: `RESEARCH_ONLY_EVO2`

## Решение

`E2.6 Replicated Causal Experiments` принят по human-directed exact-attached-Godot equivalent fresh behavioral execution gate.

Это не independent Reviewer/Verifier PASS. Fresh process и exact carrier доказывают свежесть исполнения, но не независимость actor/session.

Следующий research checkpoint: `E2.7 Cross-Seed Robustness` — `AUTHORIZED_NOT_STARTED`.

## Exact code under test

```text
8ac37bfea0f36731407e1252db1a7c2a2305420e
```

От принятого E2.5 carrier `4fb0c0ec5010251373b61b5a507604ff82f2d6e5` до code freeze ровно три executable/test transport commits:

```text
scripts/research/ecology/plant_replicated_causal_experiments_v1.gd
tests/research/ecology/eco_evo2_e2_6_replicated_causal_experiments_acceptance.gd
RUN_ECO_EVO2_E2_6_TESTS.ps1
```

Implementation blob:

```text
7fb18d91ba59493c608edafba610dc882152852a
```

Acceptance-test blob:

```text
55b9af8b1969b033606fab112accd616eee8122a
```

Runner blob:

```text
08a2ffbfbe1b3c28b020571256b6831d37d97fcb
```

## Parent pins

```text
E2.5 aggregate
942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6

E2.5 code-under-test
4c17a91957e392eabc04e136f9590773dbe54dd1

E2.4 aggregate
ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5

E2.4 plan
f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0
```

Frozen E2.2 artifact remains:

```text
bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## Replication protocol frozen before execution

Replicate set:

```text
R01
R02
R03
R04
R05
```

Hard rule:

> все пять replicate records остаются в evidence независимо от результата. Null/reversal нельзя удалить после запуска.

Predeclared acceptance threshold:

```text
positive adaptation effect     >= 4 / 5 per environment
reciprocal home advantage      >= 4 / 5 per environment
```

Environment set:

```text
DRY
WET
```

Control/Treatment сохраняют exact E2.5 causal design:

```text
CONTROL
same frozen founders
+ same environment
+ same replicate stream
+ mutation_probability = 0
        ↓
ecological sorting only

TREATMENT
same frozen founders
+ same environment
+ same replicate stream
+ exact accepted E2.5 bounded mutation policy
        ↓
mutation → inherited descendants → ResourceModel selection
```

Only deliberate treatment variable: permission for bounded continued adaptation.

## Small exact executable closure

E2.6 намеренно не re-executes весь E2.4/E2.5 graph. Accepted E2.5 выступает immutable parent contract; replicated assay использует только causal primitives, необходимые для повторения его локального adaptation mechanism.

Exact closure:

```text
7 / 7 PASS
```

```text
environment_sample_v1.gd
7ae8cc2534940ceb3c69879f8850467ba32fea8c

plant_genome_v1.gd
6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd

plant_lineage_record_v1.gd
0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0

plant_mutation_lineage_kernel_v1.gd
7b9b5d41236cb27256dd7405201436a71a3eafea

plant_resource_model_v1.gd
26fd4118307f098bd85b6d4b953a27ad8b9d85cd

plant_replicated_causal_experiments_v1.gd
7fb18d91ba59493c608edafba610dc882152852a

eco_evo2_e2_6_replicated_causal_experiments_acceptance.gd
55b9af8b1969b033606fab112accd616eee8122a
```

## Exact Godot verification

```text
Godot
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Parser/preload:

```text
exit 0
ERROR lines 0
log SHA-256
7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2
```

Fresh behavioral processes:

```text
process A exit 0
process B exit 0
218 / 218 assertions PASS
ERROR lines 0 / 0
logs byte-identical
log SHA-256
a1dec9651244fb1ccf95a617469d56a4b7d674aceb6f73bf33e792a3c9a82307
```

Canonical PowerShell runner exists, but `pwsh/powershell` was unavailable in the Linux carrier. The equivalent gate reproduced its exact parent, 7/7 closure, parser, fresh-process, PASS-marker and frozen-output predicates.

## Frozen outputs

```text
aggregate
1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd

replicate set
5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637
```

DRY:

```text
mean adaptation gain     0.235359270024
positive replicates      5 / 5
home-advantage reps      5 / 5
aggregate hash
10ca9de3ca7989494507bcb081a410bd1e8e625faa10843f62201c258e9bdd52
```

WET:

```text
mean adaptation gain     0.379178153879
positive replicates      5 / 5
home-advantage reps      5 / 5
aggregate hash
3fa2b4a96a141241e367d56b7fa69f6d8bc9f92f32cd5266128248c21a092755
```

Replicate hashes:

```text
R01 36b5d458d037cafe6c1d72bb68040876a2a453637d68d89de75dae98f9e7fa84
R02 c3e2dbc3949c6d16edc646954b1a324b0e03215aae7a1759ec3d79bfd8a64177
R03 d808be565e5d1c39725b5212b72e85efb4113f3e11e27dc3f560da515d455477
R04 9785a696f335895b48dde1dc2813bde5f872bf887f9664c3ec122dba789c4ca4
R05 a815a398caf1845da32ea4fdc7e7462e42e36c4580393bac0b215cbbef71f4f9
```

## What E2.6 proves

Within the frozen synthetic E2.2/E2.5 research contract:

- ecological sorting remains the Control mechanism;
- Treatment uses the same founders/environment and changes only adaptation permission;
- the E2.5 adaptation effect is reproduced across all five predeclared deterministic variation streams;
- every replicate is retained in evidence;
- DRY and WET both exceed the frozen 4/5 positive-effect threshold;
- DRY and WET both exceed the frozen 4/5 reciprocal-home-advantage threshold;
- descendants remain inside the same research species/lineage identities;
- global RNG is not consumed;
- dropping or reordering replicates fails closed;
- fully rehashed causal-effect tamper is rejected by deterministic replay.

## What E2.6 does not prove

Not claimed:

- formal p-value/statistical significance;
- broad cross-seed robustness;
- robustness across alternative bake/catalog seeds;
- full continuous transfer+evolution dynamics;
- canonical species formation;
- production authority;
- independent Reviewer PASS;
- independent Verifier PASS.

Those boundaries matter: five successful deterministic replicate streams are evidence of **replication**, not yet the larger robustness claim assigned to E2.7.

## Decision

```text
ACCEPT E2.6
AUTHORIZE E2.7 Cross-Seed Robustness
```
