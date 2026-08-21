# ECO.P1A — Environmental Causality Baseline — ACCEPTED

## Итоговое решение

`ECO.P1A ACCEPTED`.

S5 не добавляет новую экологическую математику. Он сводит уже принятые S1–S4 и проверяет, что вся причинная база достаточно устойчива, чтобы открыть mutation/selection experiments.

## Evidence chain

- **S1 Environment Contracts + Deterministic Fixture** — `109/109`, accepted environment hash `b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`.
- **S2 Single-Plant Resource Model** — `235/235`, accepted simulation hash `618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c`.
- **S3 Diagnostic Visual Lab + Controlled Trait Probes** — `208/208`, dataset hash `dff41c7b5ae3e2744b957ea0dd81fa3830de6365711b34d66024115509aa3690`, scene hash `9713cd410b54731fb151893ea78bec056672e6ad344c47a10046ab34d5dd2a7c`, graphical PASS after Fix1.
- **S4 Determinism, Sensitivity and Failure Classification** — `165/165` + fresh-process restart replay `5/5`; summary/result/biomass-series hashes matched exact Windows baseline.

## P1A gate — 10/10 PASS

1. Environment deterministic и seam-safe — PASS.
2. Environment truth не зависит от camera/LOD/presentation — PASS.
3. Один fixed genome создаёт spatially different viability/biomass — PASS.
4. Local result объясняется resource/cost breakdown — PASS.
5. Нет hardcoded biome placement logic — PASS.
6. Есть реальный structural trade-off — PASS: root depth не является free trait.
7. Same seed/revision даёт identical hashes, включая fresh-process restart — PASS.
8. Controlled probes ожидаемо сдвигают niche — PASS.
9. Biomass bounded, без total extinction/runaway в baseline — PASS.
10. Visual lab и headless evidence используют одну truth-модель — PASS.

## Что именно доказано

P1A доказывает, что текущая research ecology base достаточно причинна и воспроизводима для следующего эксперимента. Environment задаётся непрерывными полями, fixed genome отвечает на них через явные resource benefits/costs, а trade-offs не дают бесплатного универсального улучшения.

Это **не** означает, что уже доказана полноценная экосистема. Ещё не доказаны mutation/selection, lineage history, dispersal-limited range, species competition, succession, food webs, production authority/persistence/networking или rich canonical substrate integration.

## Решение об эволюции

Открыть `ECO.P1B — Local Adaptation Proof`.

Главное правило P1B:

> Стартуем от **одного ancestor**. Controlled probes S3 остаются только диагностическими reference points и не используются как заранее заданные виды. Mutation + selection должны сами обнаружить локально выгодные стратегии.

Минимальный ожидаемый результат P1B:

- one ancestor population;
- deterministic mutation stream;
- inherited ecological traits;
- selection только через accepted P1A resource consequences;
- региональное расхождение trait distributions;
- lineage/provenance evidence;
- same seed -> same evolution hash;
- разные seeds могут расходиться по конкретным genomes, но должны сохранять феномен specialization.

## Параллельный lane

После P1A также разрешён `ECO.PH0 — Development Trait Contract` как research-only contract work.

PH0 не должен менять принятую P1A ecology truth. Запрещено вводить canonical `TREE/BUSH/GRASS` types или делать renderer частью genome/resource hashes.

## Что остаётся заблокировано

- production runtime promotion;
- planet-wide authoritative ecology;
- per-individual network replication;
- duplicate persistence/authority foundations;
- ownership geology/hydrology/material truth;
- production environment adapter до актуального canonical G query contract;
- rich substrate behavior до canonical Material Ontology projection.

Следующий основной checkpoint: **`ECO.P1B Local Adaptation Proof`**.
