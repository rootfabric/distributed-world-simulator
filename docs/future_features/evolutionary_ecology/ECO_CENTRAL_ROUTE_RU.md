# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / CAL1-A EXECUTE_NOW`.

## Текущее состояние

Доказана и принята цепочка:

`Environment -> Genome -> Phenotype -> GrowthGraph -> Morphology Costs/Benefits -> Selection -> Seed Lifecycle -> PlantRenderDescription -> Real 3D Materialization -> Multi-Scale Representation`.

`ECO.PH RESEARCH COMPLETE`.

После PH5 выполнен `ECO.CONV0-A` global consumer-requirements review. Вывод: evolutionary ECO не требует нового global foundation; будущая production integration должна использовать canonical `TF / SD / ENV / MAT / WQ / POP / LIFE / WB / NX / WT / COMPAT`.

CONV0-A выявил пять R3 gaps, включая два high-architecture:

1. `ECO` program-ID collision: evolutionary ecology vs future world economy — economy следует именовать `ECON`;
2. ECO ecological population semantics vs generic `POPULATION_FIELD` ownership — нужен adapter boundary, не два population fabrics.

Полный gap report:

`docs/future_features/evolutionary_ecology/ECO_CONV0_A_R3_GAP_REPORT_RU.md`.

## Центральный маршрут

```text
       ECO.PH RESEARCH COMPLETE
                ↓
          CONV0-A ACCEPTED
                ↓
          CAL1-A EXECUTE_NOW
       baseline decomposition
                ↓
          CAL1-B relative
       vertical light competition
                ↓
          CAL1-C crown/root
             competition
                ↓
          CAL1-D lifetime /
        reproduction / disturbance
                ↓
          CAL1-E combined matrix
                ↓
          CAL1-F calibration /
          full-pool robustness
                ↓
          CAL1 ACCEPTED
                ↓
               P2
 dispersal / recruitment / biogeography
                │
                ├───────────────┐
                │               │
                │       CONV0-B when canonical
                │       R3/WQ/MAT/POP/LIFE/WB
                │               │
                └───────┬───────┘
                        ↓
             WAIT FOR FOUNDATIONS
                        ↓
                       P3
                        ↓
                      PH6
```

## CAL1 — Morphology Economics Calibration

Plan:

`docs/future_features/evolutionary_ecology/ECO_CAL1_MORPHOLOGY_ECONOMICS_PLAN_RU.md`.

Known finding:

`HEIGHT_LOW/full-pool dominance`.

Source audit показывает структурную асимметрию текущей модели:

```text
height benefit
  -> absolute shade_pressure(environment)

height cost
  -> structural_cost ~ height^1.55
```

При этом отсутствует главное relative benefit path:

```text
neighbour height / canopy overlap
      ↓
vertical light competition
      ↓
relative canopy exposure
```

Поэтому первое правило CAL1:

> Не калибровать коэффициенты до проверки missing causal mechanisms.

### CAL1-A — EXECUTE_NOW

Построить deterministic baseline decomposition для полного strategy pool по environment matrix.

Для каждой стратегии фиксировать realized morphology и все существующие PH3 score components. Никаких coefficient changes.

CAL1-A должен:

- воспроизвести `HEIGHT_LOW` dominance, а не скрыть его;
- показать, какие terms создают margin;
- сохранить accepted PH3C pairwise behavior;
- получить deterministic/restart baseline hash.

### CAL1-B — NEXT

Relative vertical light competition с causal controls `NO_NEIGHBOURS`, `EQUAL_HEIGHT`, `TALL_VS_SHORT_DENSE`, `TALL_VS_SHORT_SPARSE`, `DRY_DENSE`, A/B swap symmetry.

Цель:

`height may become beneficial because of competitors`,

а не `tall always wins`.

### CAL1-C/D/E/F

Дальше: crown/root overlap, lifetime/reproduction/dispersal/disturbance payoffs, combined mechanism matrix, и только затем coefficient calibration + full-pool robustness.

После CAL1 открывается P2.

## P2 — Dispersal / Recruitment / Biogeography

- P2.1 Seed Dispersal Kernel;
- P2.2 Establishment / Recruitment;
- P2.3 Local Population Turnover;
- P2.4 Patch Colonization;
- P2.5 Disturbance + Recovery;
- P2.6 Long-Horizon Biogeography;
- P2.7 Speciation Candidate Diagnostics.

Цель: lineage divergence возникает из migration + environment + competition + history, а не из hardcoded biome/species placement.

## CONV0-B

`WAIT_CANONICAL_R3_FOUNDATION_CONTRACTS`.

После canonical R3 и реальных `WQ/MAT/POP/LIFE/WB/ENV` contracts выполнить compatibility/freeze. До этого не создавать ECO-private production substitutes.

## Production boundary

`P3/PH6` остаются blocked до canonical foundations + fresh PC0/Harness-controlled runtime frontier.

Запрещены:

- ECO-private WorldAddress/WQ/material registry;
- generic ECO population runtime fabric вместо POP;
- ECO lifecycle/authority/persistence/transport;
- ECO global scheduler вместо WB;
- planet-wide individual GrowthGraph truth;
- переход `PH5 -> PH6` напрямую.

## Global project alignment

ECO служит global North Star четырьмя способами:

1. **canonical truth integrity** — ecology state не дублируется renderer/runtime foundations;
2. **incremental representation** — PH5 доказал disposable LOD от FULL до POPULATION_ONLY;
3. **parallel convergence** — CONV0-A заранее выявил R3 intersections/gaps, не блокируя runtime critical path;
4. **distributed living world** — CAL1/P2 строят population-scale causal ecology, которую позже можно подключить к POP/LIFE/WB вместо миллионов постоянно активных plant objects.
