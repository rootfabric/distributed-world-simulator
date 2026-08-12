# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / OPERATIONAL ROUTE`.

Этот документ задаёт центральный маршрут ветки `feature/eco-evolutionary-ecology` после завершения доказательной цепочки P1 и перехода к развитию representation/integration. Он отвечает на вопрос: **что делать дальше, в каком порядке и какие этапы нельзя перескакивать**.

## Текущее состояние

Уже доказана цепочка:

`Environment -> Genome -> Phenotype -> GrowthGraph -> Morphology Costs/Benefits -> Selection -> Seed Lifecycle -> PlantRenderDescription -> Real 3D Materialization`

Приняты: `ECO.P1`, `PH0`, `PH1`, `PH2`, `PH3`, `PH3C`, `PH4`, `PH5-S1`.

`PH5-S2` после exact Windows + fresh-process replay + graphical user observation считается принятым. Следующий исполняемый этап: `PH5-S3`.

## Центральная дорожная карта

```text
                  PH5-S2 ACCEPTED
                         │
                         ▼
              PH5-S3 Multi-scale LOD
                         │
                         ▼
              PH5-S4 Robustness
                         │
                         ▼
              ECO.PH RESEARCH COMPLETE
                         │
                ┌────────┴────────┐
                ▼                 ▼
          ECO.CONV0            ECO.CAL1
        World contracts     morphology economics
                │                 │
                │                 ▼
                │               ECO.P2
                │      dispersal / recruitment /
                │           biogeography
                │                 │
                └────────┬────────┘
                         ▼
                WAIT FOR FOUNDATIONS
         World Query + Material Ontology
          + Spatial/Work Budget + Harness
                         │
                         ▼
                      ECO.P3
          controlled world integration
                         │
                         ▼
                     ECO.PH6
        promoted persistent individuals
```

## Операционный resolver

При продолжении ветки:

1. прочитать machine roadmap `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`;
2. выполнить `current_step`;
3. после acceptance перечитать roadmap;
4. не выполнять этапы, помеченные `BLOCKED`/`DEFERRED`;
5. не переносить runtime ownership в ECO.

## PH5-S3 — Multi-Scale Plant Representation

Цель: доказать, что одна и та же ecological truth может иметь radically different representation cost.

Предлагаемые tiers:

- `TIER_0_FULL` — promoted/hero individual, detailed branch tubes + foliage;
- `TIER_1_REDUCED` — reduced GrowthGraph representation;
- `TIER_2_CANOPY` — canopy/cluster approximation;
- `TIER_3_IMPOSTOR` — billboard/impostor;
- `TIER_4_POPULATION_ONLY` — population field, без materialized individual GrowthGraph.

Ключевой invariant:

`LOD / distance / screen size / renderer profile != ecology state / species / identity / authority`.

Far population patches не обязаны существовать как миллионы `Node3D`/GrowthGraph instances.

## PH5-S4 — Visual Robustness / Handoff

Проверить матрицу contrasting phenotypes × representation tiers × renderer profiles × deterministic seeds.

Обязательные свойства:

- неизменность GrowthGraph/ecology/resource/selection/lifecycle truth;
- deterministic presentation descriptors;
- switching/dematerialization/rematerialization;
- bounded resource usage;
- отсутствие renderer -> ecology обратного пути;
- graphical transitions near/mid/far/population-only.

После acceptance: `ECO.PH RESEARCH COMPLETE`.

## ECO.CONV0 — World Integration Contracts

Статус после PH5-S4: `DESIGN/CONTRACT LANE`, не runtime implementation.

ECO должен описать только границы потребления/проекции:

`WorldAddress + time/history -> EcoEnvironmentQuery -> temperature/moisture/sunlight/nutrients/flood/disturbance/substrate projection`

и обратный derived output:

`EcoPopulationProjection -> population/species-candidate/phenotype distribution/biomass/density/development distribution/render hints`.

Ownership реализации остаётся у canonical World Query / G / Matter / runtime foundations.

Нельзя создавать ECO-private версии Spatial Fabric, Material Ontology, persistence, authority, transport или global work budget.

## ECO.CAL1 — Morphology Economics Calibration

Перед unrestricted morphology evolution требуется закрыть известный риск `PH3C_FULL_POOL_COMPACT_DOMINANCE`.

Принцип: не подгонять коэффициенты под красивый результат. Сначала проверять отсутствующие causal mechanisms, например:

- neighbour/self shading;
- vertical light competition;
- crown overlap;
- root overlap/below-ground competition;
- size-dependent reproduction;
- dispersal benefit from height;
- long-lived structural payoff;
- disturbance resistance.

Порядок: `missing mechanism -> causal experiment -> calibration -> full-pool robustness`.

До CAL1 acceptance запрещено заявлять unrestricted morphology/species emergence.

## ECO.P2 — Dispersal / Recruitment / Biogeography

После CAL1 основная research-линия:

- P2.1 Seed Dispersal Kernel;
- P2.2 Establishment / Recruitment;
- P2.3 Local Population Turnover;
- P2.4 Patch Colonization;
- P2.5 Disturbance + Recovery;
- P2.6 Long-Horizon Biogeography;
- P2.7 Speciation Candidate Diagnostics.

Цель: lineage divergence должен возникать из migration + environment + resource competition + history, а не из hardcoded biome/species placement.

## ECO.P3 и PH6 — только после production foundations

Не начинать production world integration, persistent detailed plants или networked individual vegetation до появления canonical foundations:

- World Query Fabric / current canonical G environment contracts;
- Unified Material Ontology projection;
- Spatial Domain Fabric / representation identity boundary;
- Promotion/Dormancy/Demotion semantics;
- World Work Budget;
- canonical authority/persistence/transport integration;
- fresh PC0/Harness-controlled runtime frontier.

После этих gates:

`ECO.P3 -> controlled world integration -> ECO.PH6 promoted persistent individuals`.

PH6 хранит detailed development/damage/pruning state только для promoted/interacted individuals; planet-wide individual GrowthGraph truth запрещён.

## Network convergence principle

Будущая сеть должна по возможности передавать population/domain truth, а не каждое дерево:

`server ecology population state -> client deterministic derived representation`.

Индивидуальный сетевой/persistent object появляется только через explicit promotion boundary при interaction/damage/ownership-relevant state.

## Главный порядок

1. `PH5-S2 ACCEPTED`.
2. `PH5-S3`.
3. `PH5-S4`.
4. `ECO.PH RESEARCH COMPLETE`.
5. Открыть `ECO.CONV0` и `ECO.CAL1` как независимые non-runtime lanes.
6. `CAL1 -> P2`.
7. Ждать production foundations.
8. Только затем `P3 -> PH6`.

Этот порядок является центральным маршрутом ECO и имеет приоритет над старым линейным прочтением `PH5 -> PH6`.
