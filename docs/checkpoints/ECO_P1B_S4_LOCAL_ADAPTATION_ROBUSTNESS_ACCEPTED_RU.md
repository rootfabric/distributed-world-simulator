# ECO.P1B-S4 — Local Adaptation Robustness Gate — ACCEPTED

## Статус

`ACCEPTED / EXACT_WINDOWS_PASS`.

S3 доказал spatial trait-environment divergence на одной неоднородной карте. S4 не добавляет новую экологическую механику: это robustness/acceptance gate над тем же `PlantRegionalPopulationFieldV1`.

## Зачем нужен S4

Один красивый seed недостаточен для принятия local adaptation. Нужно доказать, что результат не является артефактом конкретной deterministic mutation sequence или слишком короткого горизонта.

S4 проверяет несколько независимых evolution seeds, neutral control, более длинный run, одинаковые знаки regional specialization, отсутствие runaway traits и fresh-process replay.

## Baseline и результат

Robustness runs: grid `5×5`, `4` individuals на patch, `9` generations, `2` offspring на parent, seeds `918221`, `918222`, `918223`. Long run — `12` generations.

Средние значения по трём seeds:

- final accepted net resource balance: `+0.165354`;
- `water_preference ↔ moisture`: `+0.900298`;
- `root_depth ↔ moisture`: `-0.538061`;
- `shade_tolerance ↔ sunlight`: `-0.421823`.

Neutral control при тех же spatial mechanics не воспроизводит реальный pattern: water/moisture `-0.055102`, root/moisture `-0.033544`, shade/sunlight `+0.235387`.

На `12` generations specialization сохраняется: final net `+0.248580`, water/moisture `+0.889291`, root/moisture `-0.582872`, shade/sunlight `-0.458818`.

## Determinism baseline

- aggregate hash: `2c37160726c73a9b6b479be67a3cedcd34a1247025b219d2b5ebddbec4e18f05`;
- neutral hash: `175bbef1c085d0783bd0d48f23bbc9a865cc438ae09e15785d4e48cdf1cc27bf`;
- long-run hash: `7f68ed87e10fa7dd6f9f79c6d50d0a82cf4360e4a416dc481e0e6005bcfb44f3`.

## Exact Windows acceptance

- P1A-S1 `109/109`; P1A-S2 `235/235`; P1A-S3 `208/208`; P1A-S4 `165/165`;
- P1B-S1 `5834/5834`; P1B-S2 `364/364`; P1B-S3 `388/388`;
- P1B-S4 `86/86`; fresh-process replay `5/5`;
- aggregate/neutral/long-run hashes совпали точно.

Decision: **ACCEPTED**.

Следующий aggregate decision: `ECO.P1B Local Adaptation Proof`.
