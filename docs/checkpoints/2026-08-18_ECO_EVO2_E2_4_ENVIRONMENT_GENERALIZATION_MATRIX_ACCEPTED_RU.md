# ECO.EVO2 / E2.4 Environment Generalization Matrix — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Scope: `RESEARCH_ONLY_EVO2`

## Решение

`E2.4 Environment Generalization Matrix` принят по human-directed exact-attached-Godot equivalent fresh behavioral execution gate.

Это не independent Reviewer/Verifier PASS. Fresh process и exact carrier доказывают свежесть исполнения, но не независимость роли.

Следующий research step: `E2.5 Ecological Sorting vs Continued Adaptation` — `AUTHORIZED_NOT_STARTED`.

## Exact code under test

```text
0135aee461a107375cdb3e52e07e8c799145998b
```

Implementation:

```text
scripts/research/ecology/plant_environment_generalization_matrix_v1.gd
823ef6445d7f71aee79b7c0bb0932b321f90ce8d
```

Acceptance test:

```text
tests/research/ecology/eco_evo2_e2_4_environment_generalization_matrix_acceptance.gd
e365aafe7cb703d6cc26e812b8e1ea0c7716de35
```

Runner:

```text
RUN_ECO_EVO2_E2_4_TESTS.ps1
2b967fd42501a53f53c0cd4c51e534dd59c8f542
```

## Frozen parents

```text
E2.3 aggregate  82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
E2.3 code HEAD  c7ee41371807ed7dbb75e7e1eae1587105873a26
E2.2 bake       45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
E2.2 catalog    5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## Matrix

Один и тот же frozen catalog прогнан через:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

Ни одна cell не получает target-aware species list или rebake.

`HIGH_SEASONALITY` имеет bounded semantics:

```text
SEASONAL_ENVELOPE
  COOL_WET
  MILD
  HOT_DRY
  COOL_DARK
```

Все четыре phase используют один стабильный unseen patch ID `target/e24-high-seasonality`, но разные exact EnvironmentSample. Это extreme-envelope portability probe, а не claim непрерывной seasonal population dynamics.

`PATCH_ISOLATED` использует exact тот же environment checksum, что `NEAR_SOURCE`, но географически недостижим. Это causal control против ложной колонизации по одной suitability.

## Canonical execution carrier

До behavioral execution был проверен полный transitive executable closure:

```text
18 / 18 exact Git blobs PASS
```

Inherited E2.3 dependencies: `16` exact unchanged blobs.  
New E2.4 implementation/test: `2` exact published blobs.

## Exact Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Parser/preload:

```text
exit 0
log SHA-256 7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2
```

Fresh behavioral execution:

```text
process A exit 0
process B exit 0
82 / 82 assertions PASS
logs byte-identical
log SHA-256 23ac2294dbe9b7ad0f78f7807e0bde67eb804b4e2f8640f711afdc71b5d0f40c
```

`pwsh`/`powershell` отсутствуют в текущем Linux carrier, поэтому canonical `.ps1` не запускался. Equivalent gate воспроизвёл parent pins, exact closure, parser, behavioral assertions, fresh-process determinism и frozen output predicates.

## Frozen outputs

```text
matrix
 ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5

plan
 f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0

NEAR_SOURCE
 04090e13c45e780bfb88f311362f10f7c48e4ce4bb1f2182cb400f72472796c4

DRY
 b4172292008caac01921c5636f9a287e38cd64a96d855c1d581fa76cc963179e

WET
 37590db6149b575da162a225fdef2018e8954a6360d888bc673b8a7e7a82461d

NUTRIENT_POOR
 7d4f55c70c762979ea9ce1abbe1d241a5e0a4bce2d30dadb30e93f68e46c0ef1

HIGH_SEASONALITY
 7f23b7b873bc9ceb4773efb7678931e22f251f547a85622b27d48db4aa1fd103

PATCH_ISOLATED
 3cb766a7aacf2e04a22a5515543ea9a47eb55e94be62f353018f95dd400a8b8a
```

Observed outcome class:

```text
NEAR_SOURCE       COLONIZED year 1
DRY               COLONIZED year 1
WET               COLONIZED year 1
NUTRIENT_POOR     COLONIZED year 1
COOL_WET          COLONIZED year 1
MILD              COLONIZED year 1
HOT_DRY           COLONIZED year 1
COOL_DARK         COLONIZED year 1
PATCH_ISOLATED    VALID_NO_COLONIZATION
```

Колонизация во всех reachable cells не означает одинаковую ecology: static environment challenges дают разные final population states/histories, а seasonal envelope даёт несколько distinct ecological states.

## Findings, закрытые до freeze

### E2_4_CONTRACT_001_CANONICAL_PLAN_REBUILD

Initial plan validator подавал уже canonical phase records обратно в strict raw-input boundary. Исправлено: validation теперь самостоятельно восстанавливает raw typed phase input и canonical rebuild exact-compares plan.

### E2_4_EVIDENCE_002_FULLY_REHASHED_RESULT_TAMPER

Negative test усилен: после semantic tamper пересчитываются phase/cell/matrix hashes. Validation всё равно обязана отвергнуть artifact через deterministic replay mismatch.

## Accepted research claims

E2.4 доказывает в пределах frozen synthetic E2.2 artifact lineage:

- один catalog переносится на шесть controlled environment/geography classes;
- environment challenge меняет population state/history без изменения catalog;
- target starts empty во всех probes;
- evolution/mutation остаётся disabled;
- no biome-to-species lookup;
- geographic isolation не создаёт fabricated population truth;
- multiple seasonal extreme snapshots одного unseen patch дают разные deterministic ecological trajectories;
- same input deterministic across fresh processes;
- no global RNG consumption;
- plan/bake не мутируются;
- fully rehashed semantic tamper rejected by replay.

## Не заявляется

- continuous seasonal population dynamics;
- real evolution-bake producer integration;
- canonical biological taxonomy;
- production authority;
- independent Reviewer PASS;
- independent Verifier PASS.
