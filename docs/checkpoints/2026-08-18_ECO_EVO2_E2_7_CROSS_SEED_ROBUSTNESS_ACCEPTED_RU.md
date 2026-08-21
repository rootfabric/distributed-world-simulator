# ECO.EVO2 / E2.7 — Cross-Seed Robustness — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Статус: `ACCEPTED / RESEARCH_ONLY`.

## 1. Exact accepted carrier

```text
code-under-test
52f31ca58a77296d63b1642954659edcbd12b8fe

parent E2.6 aggregate
1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd

parent E2.6 code-under-test
8ac37bfea0f36731407e1252db1a7c2a2305420e

parent E2.6 replicate-set
5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637
```

E2.7 executable candidate относительно последнего E2.6 durable carrier состоит ровно из пяти новых файлов: orchestration, causal protocol, evidence validator/statistics, acceptance test и canonical runner. Production/runtime paths не менялись.

## 2. Research question

E2.6 доказал reproducibility одного causal protocol внутри заранее объявленного набора `R01..R05`. E2.7 отвечает на следующий, более строгий вопрос:

> сохраняется ли причинный вывод `frozen sorting + bounded continued adaptation` при смене seed-family namespace, без post-hoc удаления неудачных seed и без изменения среды, catalog или mutation policy?

E2.7 не меняет научный механизм. Он меняет только набор deterministic seed families.

## 3. Frozen protocol

```text
cells                  DRY / WET
seed families          S01..S10
generations            10
population             8
offspring per parent   4
```

Контроль и Treatment используют:

- exact два frozen E2.2 genomes;
- exact DRY/WET environments из принятого E2.4;
- exact E2.5 Control/Treatment policy hashes;
- exact deterministic MutationKernel;
- exact ResourceModel;
- один и тот же founder set внутри каждой Control/Treatment пары.

Единственная deliberate treatment difference — mutation permission.

Predeclared acceptance thresholds:

```text
positive adaptation effect per cell     >= 8 / 10
reciprocal home advantage per cell      >= 8 / 10
full seed pass                           >= 7 / 10
q25 adaptation gain                      > 0
median adaptation gain                   > 0
minimum leave-one-out mean              > 0
```

Все десять seed обязаны сохраняться в artifact. Censoring запрещён.

## 4. Implementation artifacts

```text
scripts/research/ecology/plant_cross_seed_robustness_v1.gd
f980a6132835cd2c483d5210615579ddccf7e618

scripts/research/ecology/plant_cross_seed_protocol_v1.gd
8d28fb09ac6e3f8b46594b39f76db69c2b6f9b17

scripts/research/ecology/plant_cross_seed_evidence_v1.gd
940ed657b7aa85758ac33088634d1ce5fdc4e673

tests/research/ecology/eco_evo2_e2_7_cross_seed_robustness_acceptance.gd
334a833acd1d0bc32ee03f0977d764ff5e517196

RUN_ECO_EVO2_E2_7_TESTS.ps1
6da8290ec1944d704a778e3b1ce8910260e5b5cb
```

Разделение на orchestration/protocol/evidence сделано специально: scientific execution, semantic replay validation и checkpoint aggregation имеют разные responsibilities и отдельные exact blob identities.

## 5. Exact executable closure

Canonical behavioral carrier проверен на exact transitive GDScript closure:

```text
9 / 9 PASS
```

```text
environment_sample_v1.gd                 7ae8cc2534940ceb3c69879f8850467ba32fea8c
plant_genome_v1.gd                       6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd
plant_lineage_record_v1.gd               0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0
plant_mutation_lineage_kernel_v1.gd      7b9b5d41236cb27256dd7405201436a71a3eafea
plant_resource_model_v1.gd               26fd4118307f098bd85b6d4b953a27ad8b9d85cd
plant_cross_seed_robustness_v1.gd        f980a6132835cd2c483d5210615579ddccf7e618
plant_cross_seed_protocol_v1.gd          8d28fb09ac6e3f8b46594b39f76db69c2b6f9b17
plant_cross_seed_evidence_v1.gd          940ed657b7aa85758ac33088634d1ce5fdc4e673
E2.7 acceptance test                      334a833acd1d0bc32ee03f0977d764ff5e517196
```

Особенно важно: опубликованные GitHub bytes были восстановлены и сверены именно по Git blob SHA до behavioral verification. Предыдущий локальный probe с похожими, но не exact blobs не использовался как acceptance evidence.

## 6. Fresh behavioral verification

Exact Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
binary SHA-256
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Результат на freeze HEAD carrier:

```text
parser/preload           PASS
parser exit              0
parser ERROR lines       0
parser log SHA-256       7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2

fresh process A          PASS
fresh process B          PASS
assertions               290 / 290 PASS
ERROR lines              0 / 0
A/B logs                 byte-identical
behavior log SHA-256     51c421e5e3f909cc265bd8180fa1bd9a56f1f5e3a1e727a5010a5667d40156a9
```

Canonical PowerShell runner существует, но `pwsh/powershell` отсутствуют в Linux carrier. Поэтому acceptance authority классифицирована как:

`EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`.

Canonical-runner execution **не заявляется**. Independent Reviewer/Verifier PASS **не заявляется**.

## 7. Frozen result

```text
E2.7 aggregate
 eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d

seed ensemble
 a49ce9d6856e08e1e0a61f060a8019de61685cdc63b25229b3761c9e7c9d792f

full seed pass   10 / 10
full seed fail    0 / 10
```

### DRY

```text
mean      0.229458431680
median    0.227109019511
q25       0.218691252321
q75       0.230928849977
min       0.186805390360
max       0.279412047042
positive  10 / 10
null       0 / 10
reversal   0 / 10
home       10 / 10
LOO min mean 0.223908029973
aggregate f3b65f8c890c75243f9a089f6f3036ef937c7251d675c0fd6919f06b00522c3f
```

### WET

```text
mean      0.386587470375
median    0.388500039215
q25       0.368469916498
q75       0.391244612251
min       0.345047365361
max       0.425056726888
positive  10 / 10
null       0 / 10
reversal   0 / 10
home       10 / 10
LOO min mean 0.382313108540
aggregate 98020ab8f6bb8fb52775ac4796bc2f45ea16530e468c5324b5716f598af4989b
```

Observed 10/10 не является переписанным acceptance criterion. Formal gate оставался 8/10 positive, 8/10 home и 7/10 complete seed pass.

## 8. Integrity / anti-cherry-picking

Acceptance test fail-closed отвергает:

- удаление seed после полного rehash;
- перестановку predeclared seed после rehash;
- изменение adaptation effect с пересчётом paired/seed/aggregate hashes;
- попытку повысить result до formal statistical significance;
- попытку повысить result до cross-catalog robustness;
- production authority promotion;
- biome/species-table и hidden fitness bonus shortcuts.

Validator повторно выводит final ecological summaries, cross-environment effects, classifications, home advantage и aggregate statistics из сохранённых final populations. Поэтому простого пересчёта hash-цепочки недостаточно для semantic tamper.

## 9. Что E2.7 доказал и чего не доказал

Доказано:

- один accepted frozen catalog/protocol даёт устойчивый causal adaptation signal на десяти новых seed families;
- lower quartile и median effect положительны в обеих средах;
- удаление любого одного seed не меняет знак mean effect;
- reciprocal local adaptation сохраняется на bounded ensemble;
- вывод не зависит от одного lucky seed внутри этого ensemble.

Не доказано:

- formal statistical significance;
- robustness между разными independently evolved catalogs/bakes;
- production/runtime readiness;
- canonical biological taxonomy.

## 10. Следующий checkpoint

E2.7 acceptance открывает:

`ECO.EVO2 / E2.8 Catalog Persistence & Provenance`.

E2.8 должен доказать typed deterministic persistence portable SpeciesCatalog/evidence lineage: canonical bytes/hash, schema/version policy, restore identity, provenance chain и tamper rejection. EVO2 FINAL остаётся blocked до E2.8 acceptance.
