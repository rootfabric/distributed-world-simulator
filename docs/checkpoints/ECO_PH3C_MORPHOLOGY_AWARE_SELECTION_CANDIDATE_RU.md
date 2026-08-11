# ECO.PH3C — Morphology-Aware Selection / Competition Convergence — CANDIDATE

Статус: `ANALYTIC_PREFLIGHT_PASS / EXACT_WINDOWS_PENDING`.

PH3C проверяет не форму саму по себе, а причинную связь:

`inherited morphology -> PH2 realized phenotype -> accepted PH3 morphology ledger -> competitive abundance`.

## Causal A/B design

В каждой паре строго одинаковы:

- `PlantGenome`;
- EnvironmentSample;
- deterministic `IndividualSeed`;
- начальная abundance `0.5 / 0.5`;
- принятый P1 resource result/checksum.

Меняются только inherited developmental traits.

Каждая пара запускается дважды:

1. `RESOURCE_ONLY_CONTROL`: fitness берётся из accepted P1 base net balance. Поскольку genome одинаков, ожидается точный `0.5 / 0.5` tie.
2. `MORPHOLOGY_AWARE`: fitness берётся из PH3 coupled net balance.

Это исключает скрытый genome advantage и напрямую проверяет вклад morphology economics.

## Пары

- `SUN_CROWN`: `CROWN_NARROW` vs `CROWN_WIDE` — wide должен победить;
- `DRY_CROWN`: та же пара — narrow должен победить;
- `REFERENCE_BRANCH`: low vs high branching — low должен выиграть из-за construction/maintenance costs;
- `REFERENCE_HEIGHT`: low vs extreme high — low должен выиграть из-за super-linear structure cost;
- `REFERENCE_GIANT`: balanced BASE vs GIANT_DENSE — giant должен почти исчезнуть.

Ключевой gate — **environment-dependent selection reversal** одной и той же crown-пары: `SUN -> WIDE`, `DRY -> NARROW`.

## Analytic preflight

Независимое equation-level воспроизведение PH2 GrowthGraph + PH3 ledger сначала было сверено с уже принятым PH3 и точно воспроизвело его известные числа, включая `GIANT_DENSE morphology_delta=-2.70651869262583`.

Для PH3C при `10` cycles и selection strength `0.35` прогноз:

- SUN wide crown share ≈ `0.6498`;
- DRY narrow crown share ≈ `0.6845`;
- reference low-branch share ≈ `0.6768`;
- reference low-height share ≈ `0.8831`;
- giant-dense share ≈ `0.000144`;
- все resource-only controls = `0.5 / 0.5`.

PH3C намеренно **не** объявляет global coexistence: полный 8-way diagnostic показывает риск универсального преимущества низкой формы, поэтому текущий gate ограничен причинным доказательством morphology-aware selection. Это сохраняет fail-closed semantics и не маскирует возможную будущую calibration задачу.

Следующий шаг: exact Windows `RUN_ECO_PH3C_TESTS.ps1`. Первый зелёный Windows прогон зафиксирует canonical aggregate hash; после этого PH3C можно принять и открыть PH4 Seed Development Lifecycle.
