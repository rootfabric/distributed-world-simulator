# ECO.EVO7 — FFF3 immutable baseline freeze

**Дата:** 2026-08-24  
**Immutable subject:** `e33c72962b1b3af410c3dda28309dc844038908a`  
**Truth frontier:** `FFF3 IMPLEMENTED`; `FFF4 NOT MATERIALIZED`; `FFF5 NOT STARTED`.

## Причина фиксации

Повторный Git/tree audit обнаружил расхождение между текстом PR #213 и реальным деревом. На immutable subject присутствуют FFF0–FFF3 и multiseed evidence, но отсутствуют `soil_water_field_v1.gd`, FFF4 runner/test/checkpoint и FFF5 implementation. Исторический claim `FFF4 done / FFF5 in progress` не является authority.

Durable correction: PR #213 comment `5392328400`.

## Что считается baseline

- EVO6 rule language + generated selection continuation;
- EVO6-WATER strong water-driven selection;
- FFF0 contract mapping;
- FFF1 PlantFunctionalPhenotype;
- FFF2 morphology evolution through the single lineage authority;
- FFF3 light feedback loop;
- multiseed robustness probe.

Ни один runtime/source файл immutable subject не изменяется этой фиксацией.

## Aggregate closure runner

`RUN_ECO_EVO7_FFF3_BASELINE_CLOSURE.ps1` последовательно запускает:

1. `RUN_ECO_EVO6_RULE_SELECTION_CONTINUATION.ps1`;
2. `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`;
3. FFF0;
4. FFF1;
5. FFF2;
6. FFF3;
7. `eco_evo7_multiseed_robustness_acceptance.gd`.

Canonical Godot identity для существующей evidence-линии: `4.7.1.stable.double.custom_build.a13da4feb`.

## Уже существующее machine evidence

Project Control для exact `e33c7296...`: run `32644477247 / #1227`, conclusion `success`.

Индивидуальные FFF0–FFF3 review/verification evidence уже лежат в `docs/evidence/`. Эта freeze-запись не переименовывает их в новый aggregate independent review.

## Remaining closure gate

Для формального aggregate closure exact baseline требуется свежая независимая роль:

- REVIEWER: read-only review exact `e33c7296...` + aggregate runner result;
- VERIFIER: clean detached checkout exact `e33c7296...` + самостоятельный aggregate runner;
- никакой repair не выполняется внутри review/verification роли.

До получения этих двух свежих aggregate verdicts baseline остаётся **IMMUTABLE / MACHINE-GREEN / AWAITING AGGREGATE INDEPENDENT CLOSURE**, но его truth frontier уже однозначно FFF3.

## Следующий этап

FFF4 создаётся отдельным additive checkpoint от этой immutable базы. FFF5 запрещено смешивать с FFF4. FFF6 стартует только после доказанного FFF5. FFF7/XFER остаётся заблокирован до устойчивого FFF6.