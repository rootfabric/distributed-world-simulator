# ECO.EVO2 / E2.5 — Ecological Sorting vs Continued Adaptation — ACCEPTED

Дата: 2026-08-18.  
Ветка: `feature/eco-evolutionary-ecology`.  
Scope: `RESEARCH_ONLY_EVO2`.

## 1. Решение

E2.5 принят как bounded causal research checkpoint.

```text
E2.4 Environment Generalization Matrix     ACCEPTED
        ↓
E2.5 Ecological Sorting vs Continued Adaptation  ACCEPTED
        ↓
E2.6 Replicated Causal Experiments         AUTHORIZED_NOT_STARTED
```

Exact code-under-test:

`4c17a91957e392eabc04e136f9590773dbe54dd1`

Base before E2.5 executable changes:

`3c29e06600d911a49864d5991f6a03928612b97d`

Candidate shape до evidence carrier:

```text
3 commits
3 files

RUN_ECO_EVO2_E2_5_TESTS.ps1
scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd
tests/research/ecology/eco_evo2_e2_5_sorting_vs_adaptation_acceptance.gd
```

Production/runtime ownership не изменялся.

## 2. Parent freeze

E2.5 закрепляет accepted E2.4/E2.2 evidence:

```text
E2.4 aggregate
  ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5

E2.4 code-under-test
  0135aee461a107375cdb3e52e07e8c799145998b

E2.4 plan
  f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0

E2.2 bake
  45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

E2.2 catalog
  5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## 3. Causal design

Исследовательский вопрос E2.5 — отделить два разных механизма ответа новой среды.

### Control — ecological sorting only

```text
same frozen SpeciesCatalog
same environment
same founders
same horizon
mutation_probability = 0
        ↓
только изменение abundance существующих frozen strategies
```

### Treatment — continued adaptation

```text
same exact frozen SpeciesCatalog
same exact environment
same exact founders
same horizon
one fixed target-agnostic bounded mutation policy
        ↓
MutationKernel.reproduce
        ↓
ResourceModel.evaluate
        ↓
selection
```

Никакого target-specific fitness bonus нет. Mutation сама по себе не считается adaptation: `ADAPTATION_DETECTED` требует и novel inherited genome, и положительный measurable advantage относительно frozen sorting Control.

## 4. Implementation

```text
scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd
Git blob: 74443f7b0c1b5e2234b1949761abc6cfab4bdd9c
```

Bounded challenge:

```text
cells                  DRY / WET
generations            10
population             8
offspring per parent   4
```

Treatment policy:

```text
mutation_probability              0.30
water_preference_step             0.055
root_depth_m_step                 0.20
growth_rate_step                  0.045
shade_tolerance_step              0.045
seed_dispersal_distance_m_step    0.0
```

Policy hashes:

```text
Control
0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e

Treatment
e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416
```

Control отличается только тем, что `mutation_probability = 0`.

Adapted descendant сохраняет исходный `research_species_id` и `source_lineage_id`. E2.5 не превращает mutation в новый canonical biological species.

## 5. Behavioral evidence

Acceptance test:

```text
tests/research/ecology/eco_evo2_e2_5_sorting_vs_adaptation_acceptance.gd
Git blob: 3b2dca9fd3f15750da7a3b200ce800371f6d2021
```

Canonical runner:

```text
RUN_ECO_EVO2_E2_5_TESTS.ps1
Git blob: aac648105002a3b9337c0b7fcedfdc501d01402e
```

По Harness execution-evidence rule до behavioral execution построен полный transitive preload closure:

```text
21 / 21 exact Git blobs PASS
```

В него входят новые E2.5 files и ранее не требовавшиеся E2.4 test-closure dependencies:

```text
plant_mutation_lineage_kernel_v1.gd
  7b9b5d41236cb27256dd7405201436a71a3eafea

plant_lineage_record_v1.gd
  0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
binary SHA-256
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Fresh behavioral gate:

```text
parser/preload       PASS
fresh process A      PASS
fresh process B      PASS
assertions           93 / 93 PASS
A/B logs             byte-identical
parser log SHA-256   7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2
run log SHA-256      9aa1e912a545cdb470dbada92ba8eac5024632e2ec7f58eaef6a4ffd977975a9
```

Одна совмещённая shell-команда `parser + A + B` превысила внешний wrapper timeout уже после завершения A. Это не интерпретировалось как test result. B был запущен отдельно на том же exact carrier и завершился `0`; A/B logs byte-identical.

`pwsh/powershell` в Linux carrier отсутствует. Поэтому canonical `.ps1` runner **не заявляется выполненным**. Выполнен explicit equivalent gate, воспроизводящий parent pins, exact closure, parser, behavioral assertions, fresh-process determinism и frozen-output checks.

Это fresh execution evidence, но **не independent Reviewer/Verifier role evidence**.

## 6. Frozen result

Aggregate:

`942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6`

Paired evidence:

```text
DRY
1d8dd8f37ad0c83f439dce5493c59b38a3618f9201630a125a6197691eecab7c

WET
9234fdfa74530c1f16b90960814e88e6417b2f3f9a92a8523e825471f2dd1292
```

### DRY

```text
Control sorting detected       true
Control novel genomes          0
sorting gain                   +0.712602797217
Treatment adaptation detected  true
adaptation gain                +0.210067450172
classification                 ADAPTATION_DETECTED
```

DRY Control сортирует frozen catalog к alpha strategy. Treatment затем смещает средний `water_preference` ниже frozen sorted state.

### WET

```text
Control sorting detected       true
Control novel genomes          0
sorting gain                   +1.231209807202
Treatment adaptation detected  true
adaptation gain                +0.387714189995
classification                 ADAPTATION_DETECTED
```

WET Control сортирует frozen catalog к beta strategy. Treatment затем смещает средний `water_preference` выше frozen sorted state.

## 7. Reciprocal local adaptation

Final Treatment populations были cross-evaluated в обеих средах через тот же causal `ResourceModel`:

```text
DRY-adapted in DRY   +0.500903251638
WET-adapted in DRY   -1.600499312923

WET-adapted in WET   +1.157255352906
DRY-adapted in WET   -1.601811151164
```

То есть наблюдается reciprocal home advantage:

```text
DRY home > WET-away in DRY
WET home > DRY-away in WET
```

Это более сильный causal signal, чем просто наличие mutation events.

## 8. Fail-closed integrity

Acceptance test проверяет:

- exact parent E2.4 aggregate/head/plan;
- exact frozen E2.2 bake/catalog;
- identical initial state между Control/Treatment;
- no mutation / no novel genome в Control;
- preserved frozen research identity в Treatment;
- no global RNG consumption;
- deterministic same-process replay;
- DRY/WET sorting к разным frozen strategies;
- measurable adaptation gain;
- reciprocal cross-environment home advantage;
- tampered E2.4 matrix/bake/catalog rejection;
- semantic cross-environment tamper с пересчитанным aggregate hash rejection;
- selected mutation-event tamper с пересчитанными arm/paired/aggregate hashes rejection;
- extra field / canonical-taxonomy promotion rejection;
- отсутствие biome/species-table и target-fitness bonus shortcut.

Validator не принимает «внутренне согласованный» поддельный artifact: он независимо перестраивает ожидаемый E2.5 result и требует exact equality.

## 9. Что E2.5 доказывает и чего не доказывает

Доказано:

> При одинаковом frozen starting catalog и одинаковой новой среде ecological sorting может менять abundance без genetic change; разрешение bounded inherited adaptation создаёт новые descendant genomes с дополнительным environment-specific advantage, включая reciprocal local adaptation.

Не доказано:

- full continuous E2.3 transfer + mutation dynamics;
- replicated causal confidence;
- cross-seed robustness;
- canonical species formation;
- production authority.

Эти границы остаются явными.

## 10. Next

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.6 REPLICATED CAUSAL EXPERIMENTS
```

E2.6 должен превратить E2.5 paired result из одного deterministic assay в replicated causal evidence, не наследуя PASS автоматически.
