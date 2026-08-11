# ECO.P1B-S4 — Local Adaptation Robustness Gate — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S3 доказал spatial trait-environment divergence на одной неоднородной карте. S4 не добавляет новую экологическую механику: это robustness/acceptance gate над тем же `PlantRegionalPopulationFieldV1`.

## Зачем нужен S4

Один красивый seed недостаточен для принятия local adaptation. Нужно доказать, что результат не является артефактом конкретной deterministic mutation sequence или слишком короткого горизонта.

S4 поэтому проверяет:

- несколько независимых evolution seeds;
- один neutral control;
- более длинный run;
- одинаковые знаки regional specialization;
- отсутствие runaway traits и прижатия средних значений к biological bounds;
- fresh-process deterministic replay.

## Baseline

Robustness runs:

- grid `5×5`;
- `4` individuals на patch;
- `9` generations;
- `2` offspring на parent;
- seeds `918221`, `918222`, `918223`.

Long run:

- тот же grid/population;
- `12` generations;
- seed `918221`.

Migration/dispersal benefit ещё не моделируется, поэтому `seed_dispersal_distance_m` остаётся заморожен на `15 m`.

## Multi-seed signal

Средние значения по трём seeds:

- final accepted net resource balance: `+0.165354`;
- `water_preference ↔ moisture`: `+0.900298`;
- `root_depth ↔ moisture`: `-0.538061`;
- `shade_tolerance ↔ sunlight`: `-0.421823`.

Даже самый слабый из трёх runs сохраняет правильные знаки:

- minimum water/moisture correlation: `+0.858012`;
- weakest root/moisture correlation: `-0.524329`;
- weakest shade/sunlight correlation: `-0.340030`.

Все три seeds дают разные exact field hashes, поэтому acceptance относится к феномену, а не к одному конкретному genome trajectory.

## Neutral control

При тех же spatial mechanics и seed `918221`, но uniform environment:

- water/moisture `-0.055102`;
- root/moisture `-0.033544`;
- shade/sunlight `+0.235387`.

Neutral control не воспроизводит реальный multi-seed pattern.

## Longer horizon

На `12` generations:

- final net `+0.248580`;
- water/moisture `+0.889291`;
- root/moisture `-0.582872`;
- shade/sunlight `-0.458818`.

Regional divergence также сохраняется:

- WET minus DRY water preference `+0.154569`;
- DRY minus WET root depth `+0.355239 m`;
- SHADED minus SUNLIT shade tolerance `+0.045197`.

Средние traits остаются внутри диапазонов и не убегают к clamp boundaries.

## Determinism baseline

- aggregate hash: `2c37160726c73a9b6b479be67a3cedcd34a1247025b219d2b5ebddbec4e18f05`;
- neutral hash: `175bbef1c085d0783bd0d48f23bbc9a865cc438ae09e15785d4e48cdf1cc27bf`;
- long-run hash: `7f68ed87e10fa7dd6f9f79c6d50d0a82cf4360e4a416dc481e0e6005bcfb44f3`.

Local Godot double evidence:

- focused `86/86`;
- fresh-process replay `5/5`.

## Gate

Exact Windows должен воспроизвести эти hashes и parent regressions. После этого S4 и aggregate `ECO.P1B Local Adaptation Proof` можно принять.

Следующий этап не должен автоматически включать migration: dispersal/biogeography остаётся отдельным экспериментом, чтобы не смешивать доказательство local selection с пространственным распространением.
