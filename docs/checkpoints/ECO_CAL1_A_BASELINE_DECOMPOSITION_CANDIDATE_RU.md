# ECO.CAL1-A — Baseline Decomposition / Mechanism Audit — CANDIDATE

Статус: `IMPLEMENTED / LOCAL GODOT INTERFACE PASS / EXACT WINDOWS CANONICAL ECOLOGY GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head:

`20e083d32d8dc9ff1f4a5f3f600a49a53f7a076e`.

## Зачем этот checkpoint

CAL1-A не меняет morphology economics. Он делает существующую PH3/PH3C модель объяснимой до добавления новых механизмов.

Нужно получить baseline:

```text
4 environments
×
8 morphology strategies
×
existing PH3 benefit/cost decomposition
```

и честно ответить, за счёт каких terms `HEIGHT_LOW` получает broad full-pool advantage.

## Controlled isolation

CAL1-A использует PH3C-style isolation:

```text
same Genome
same IndividualSeed
same Environment
only morphology strategy changes
```

Это важно: старый `plant_morphology_resource_probes_v1.gd` создаёт event suffix для каждого case и поэтому не используется как ranking source CAL1-A.

## Реализовано

### Diagnostic

`scripts/research/ecology/plant_morphology_economics_baseline_v1.gd`

Для каждого strategy/environment фиксируются:

- realized graph height;
- realized max height;
- crown spread;
- branch probability;
- total branch length;
- P1 base resource balance;
- raw morphology benefit/cost components;
- signed score contributions;
- morphology benefit/cost/delta;
- selection score;
- deterministic rank;
- margin to winner;
- normalized margin;
- full-pool share после 10 cycles с PH3C selection strength;
- strongest leave-one-component-out rank sensitivity.

Environment summary дополнительно содержит:

- winner / runner-up;
- exact margin;
- strongest signed component driving winner over runner-up;
- strongest opposing component;
- `HEIGHT_LOW` rank/share;
- `HEIGHT_HIGH` rank/share;
- score delta `HEIGHT_LOW - HEIGHT_HIGH`;
- strongest component explaining that delta.

### Acceptance

`tests/research/ecology/eco_cal1_a_baseline_decomposition_acceptance.gd`

Проверяет:

- exact `4 × 8 = 32` matrix;
- same-process deterministic replay;
- PH3C aggregate hash recording;
- accepted PH3C winner semantics;
- common IndividualSeed across strategies;
- component sum reconstructs morphology delta and selection score;
- full-pool shares conserve one;
- deterministic unique ranks;
- bounded sensitivity results;
- `HEIGHT_LOW > HEIGHT_HIGH` во всех четырёх controlled environments;
- known broad `HEIGHT_LOW` full-pool advantage;
- source boundary: CAL1-A не импортирует morphology coefficient profile и не создаёт tuned profile.

### Fresh process

`tests/research/ecology/eco_cal1_a_restart_replay_probe.gd`

`RUN_ECO_CAL1_A_TESTS.ps1` запускает probe двумя отдельными Godot processes и сравнивает baseline hashes.

Runner также повторно прогоняет accepted PH3 и PH3C regressions перед CAL1-A.

## Локальная проверка

На Linux Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

новый diagnostic/test surface проверен через API-compatible synthetic stub model:

- CAL1-A acceptance: `PASS (1094 assertions)`;
- fresh-process probe: `PASS (5 assertions)` × 2;
- synthetic baseline replay exact.

Это **не canonical ecology evidence**.

Synthetic hashes не относятся к реальным PH3/PH3C данным и не должны использоваться как accepted baseline.

## Exact Windows gate

На реальном checkout выполнить:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_A_TESTS.ps1 -GodotPath $Godot
```

Нужны реальные outputs:

```text
ECO.CAL1-A REFERENCE winner=...
ECO.CAL1-A SHADE winner=...
ECO.CAL1-A SUN winner=...
ECO.CAL1-A DRY winner=...
ECO.CAL1-A Baseline Decomposition / Mechanism Audit: PASS (...)
ECO.CAL1-A baseline_hash=<64 hex>
ECO.CAL1-A legacy_ph3c_pairwise_hash=<64 hex>
ECO.CAL1-A dominance_classification=...
ECO.CAL1-A candidate automated gates: PASS
```

## Gate

До exact Windows PASS:

```text
CAL1-A != ACCEPTED
CAL1-B == BLOCKED_BY_CAL1_A_ACCEPTANCE
```

После PASS реальные component margins определят точную форму первого нового causal mechanism — `CAL1-B Relative Vertical Light Competition`.

Никакой coefficient calibration до CAL1-E не разрешена.
