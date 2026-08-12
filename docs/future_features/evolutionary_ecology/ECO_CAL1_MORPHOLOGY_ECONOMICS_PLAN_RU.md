# ECO.CAL1 — Morphology Economics Calibration / Causal Mechanism Plan

Статус: `ACTIVE RESEARCH PLAN / CAL1-A EXECUTE_NOW / RESEARCH_ONLY`.

## Зачем CAL1

PH3/PH3C доказали важную, но ограниченную вещь: morphology может причинно влиять на resource economics и selection. Они **не** доказали, что текущий набор economics mechanisms достаточен для unrestricted morphology evolution.

Наблюдаемый риск:

`PH3C_FULL_POOL_COMPACT_DOMINANCE` — `HEIGHT_LOW` получает широкое преимущество в unrestricted diagnostic.

CAL1 не должен добиваться искусственного равенства стратегий. Его задача — проверить, является ли dominance следствием реальной ecological trade-off или отсутствующего causal mechanism.

## Что показал source audit

Текущий PH3 coupling использует:

```text
height benefit
= height_light_access_gain
  × absolute shade_pressure(environment)
  × saturating(height)

structural cost
= structural_cost_scale
  × height^1.55
```

В модели отсутствует:

```text
relative plant height
relative canopy position
neighbour shading
vertical light interception
```

Следствие: высокий рост всегда платит super-linear structural cost, но почти не получает **относительного** конкурентного преимущества над низким соседом.

Это делает relative light competition первым CAL1 mechanism по причинной приоритетности.

## Неподвижные accepted boundaries

CAL1 не переписывает accepted PH3/PH3C evidence.

Legacy PH3/PH3C остаются доказательством:

- morphology/resource causal overlay существует;
- resource-only control остаётся neutral;
- crown pair reverses winner SUN vs DRY;
- construction/maintenance cost penalizes excessive branching;
- super-linear structural cost penalizes extreme height;
- giant dense morphology может быть экономически невыгодна.

Новые CAL1 experiments строятся как отдельный research layer/version.

## Принцип CAL1

```text
missing mechanism
      ↓
causal experiment
      ↓
mechanism validation
      ↓
combine mechanisms
      ↓
only then calibration
      ↓
full-pool robustness
```

Запрещён порядок:

```text
HEIGHT_LOW wins
   ↓
change coefficients until it stops winning
```

## CAL1-A — Baseline Decomposition / Mechanism Audit

Статус: `EXECUTE_NOW`.

Цель: получить machine-readable объяснение, **почему** каждая стратегия выигрывает/проигрывает до добавления новых mechanisms.

Нужно построить matrix:

```text
8 morphology strategies
×
REFERENCE / SHADE / SUN / DRY
×
score components
```

Для каждого strategy/environment сохранять:

- realized height/crown/branch/total length;
- accepted P1 base resource balance;
- height benefit;
- crown benefit;
- branch benefit;
- structural cost;
- branch maintenance/construction cost;
- crown water cost;
- morphology delta;
- final selection score;
- normalized rank/margin to winner.

Дополнительно вывести sensitivity: какой один existing component больше всего меняет rank.

### Acceptance CAL1-A

- exact deterministic baseline hash;
- repeat/restart equality;
- current `HEIGHT_LOW` dominance reproduced, not hidden;
- component decomposition identifies the dominant score terms;
- accepted PH3C pairwise matrix remains unchanged;
- no coefficient changes.

## CAL1-B — Relative Vertical Light Competition

Статус: `NEXT_AFTER_CAL1_A`.

Добавить отдельный research mechanism, который зависит не от абсолютной высоты растения, а от canopy competition context.

Минимальная модель должна учитывать:

- focal canopy height;
- neighbour canopy height distribution;
- crown overlap / local density;
- incoming sunlight;
- self/neighbor attenuation;
- fraction of canopy exposed above competitors.

Нужны causal controls:

1. `NO_NEIGHBOURS` — механизм должен давать нулевой/минимальный competitive delta;
2. `EQUAL_HEIGHT` — симметричные растения не получают fake advantage;
3. `TALL_VS_SHORT_DENSE` — высокий phenotype получает additional light access при overlap;
4. `TALL_VS_SHORT_SPARSE` — преимущество резко слабее без overlap;
5. `DRY_DENSE` — tall light advantage не должен автоматически отменять water/structure costs;
6. swap A/B должен давать симметричный результат.

### Acceptance CAL1-B

Mechanism должен доказать:

`height can be beneficial because of neighbours`,

а не:

`tall is globally better`.

## CAL1-C — Crown / Root Competition

Статус: `AFTER_CAL1_B`.

### Above-ground

Проверить:

- crown overlap;
- self shading;
- neighbour shading;
- marginal leaf area/crown benefit saturation.

Wide crown должна иметь преимущество там, где свободное light capture пространство существует, и платить за overlap/water/maintenance там, где пространство занято или среда dry.

### Below-ground

Проверить:

- root overlap;
- shared water depletion;
- shared nutrient depletion;
- depth partitioning / access differences.

Root/crown economics должны зависеть от competition context, а не только от static environment scalar.

## CAL1-D — Lifetime / Reproduction Payoffs

Статус: `AFTER_CAL1_C`.

Текущий selection score слишком близок к instantaneous resource balance. Для long-lived morphology это может систематически недооценивать expensive structure.

Проверить отдельными causal experiments:

- size-dependent reproduction;
- seed production vs reserve/biomass;
- dispersal benefit from release height;
- time-to-maturity;
- longevity / structural amortization;
- disturbance resistance / damage survival;
- recovery cost after disturbance.

Нельзя вводить один абстрактный `tall_bonus`. Каждый payoff должен иметь наблюдаемую causal interpretation.

## CAL1-E — Combined Mechanism Matrix

После individual acceptance mechanisms объединяются без coefficient calibration.

Matrix минимум:

```text
strategies
× environments
× density regimes
× disturbance regimes
```

Проверить:

- causal reversals существуют там, где меняется mechanism context;
- ни одна morphology feature не является universal free advantage;
- ни одна дорогая feature не является universal pure penalty из-за отсутствующего benefit path;
- legacy controls remain reproducible.

## CAL1-F — Calibration / Full-Pool Robustness

Только после causal mechanism acceptance разрешена calibration magnitudes.

Цель calibration — не заставить все стратегии сосуществовать. Допустимо, что некоторые strategy variants проигрывают почти везде.

Недопустимо, чтобы full-pool conclusion определялся очевидным missing mechanism или numerical artifact.

### Robustness dimensions

- multiple deterministic seeds;
- environment sweeps;
- density sweeps;
- parameter perturbation around calibrated values;
- strategy pool composition changes;
- restart determinism;
- pairwise vs full-pool consistency diagnostics.

### CAL1 final gate

CAL1 принят, когда можно честно заявить:

> morphology economics включает основные causal benefits/costs, необходимые для разрешения unrestricted morphology search; observed dominance patterns устойчивы к reasonable perturbations и не являются следствием известного missing-mechanism hole.

После этого открывается:

`ECO.P2 — Dispersal / Recruitment / Biogeography`.

## Что CAL1 не делает

CAL1 не создаёт:

- production environment integration;
- runtime population fabric;
- global scheduler;
- network replication;
- persistent individual plants;
- species catalog as hardcoded type system.

Это остаётся research-only model work внутри ECO-owned paths.

## Связь с глобальной целью проекта

CAL1 нужен не ради ботанической детализации самой по себе. Он делает будущий living world пригодным для глобальной North Star:

- canonical ecological truth может существовать независимо от presentation;
- world history/environment реально влияют на population strategy;
- future POP/LIFE/WB can change simulation resolution without changing ecology semantics;
- P2 сможет моделировать colonization/biogeography на population scale вместо ручной расстановки species/biomes.
