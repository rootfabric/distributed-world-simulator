# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / OPERATIONAL ROUTE`.

Этот документ задаёт центральный маршрут `feature/eco-evolutionary-ecology` и отвечает на вопрос: **что делать дальше, в каком порядке и какие этапы нельзя перескакивать**.

## Текущее состояние

Доказана цепочка:

`Environment -> Genome -> Phenotype -> GrowthGraph -> Morphology Costs/Benefits -> Selection -> Seed Lifecycle -> PlantRenderDescription -> Real 3D Materialization -> Multi-Scale Representation`.

Приняты:

`ECO.P1`, `PH0`, `PH1`, `PH2`, `PH3`, `PH3C`, `PH4`, `PH5-S1`, `PH5-S2`, `PH5-S3`, `PH5-S4`.

`ECO.PH RESEARCH COMPLETE`.

Accepted PH5-S3/S4 checkpoint:

`docs/checkpoints/ECO_PH5_S3_S4_MULTISCALE_REPRESENTATION_ACCEPTED_RU.md`.

Главные PH5 invariants:

- `identity != LOD`;
- representation не имеет обратного пути в ecology/resource/selection/lifecycle truth;
- FULL/REDUCED/CANOPY/IMPOSTOR/POPULATION_ONLY являются derived representation tiers;
- `POPULATION_ONLY` не требует individual plant geometry/GrowthGraph materialization.

## Global alignment после PH5

Полный разбор:

`docs/future_features/evolutionary_ecology/ECO_CONV0_GLOBAL_ALIGNMENT_RU.md`.

На момент closure PH5 canonical `main` уже содержит H0.1 R8 / C22 merge `eefd75fa3badec10c6e7db959e2a3992dba30f0e`, но main-owned registry/current dashboard ещё требуют post-C22 control synchronization. ECO не входит в runtime critical path и не имеет права использовать stale control text для production promotion.

Глобальный critical path остаётся:

```text
C22 MAIN_INTEGRATED verification / post-C22 PC0
        ↓
GLOBAL-P0 R3 exact-current-main refresh
        ↓
HUMAN R3 promotion
        ↓
post-R3 PC0
        ↓
H0.2 / NX.C1
```

ECO в это время продолжает только research/design work без runtime ownership.

## Центральная дорожная карта

```text
            PH5-S3 ACCEPTED
                   ↓
            PH5-S4 ACCEPTED
                   ↓
         ECO.PH RESEARCH COMPLETE
                   ↓
              CONV0-A NOW
     global consumer requirements
                   ↓
        ┌──────────┴──────────┐
        ▼                     ▼
      CAL1               WAIT R3/WQ/MAT
 morphology economics          │
        │                       ▼
        ▼                  CONV0-B FREEZE
       P2                       │
 dispersal/recruitment          │
 biogeography                   │
        └──────────┬────────────┘
                   ▼
          WAIT FOR FOUNDATIONS
 World Query + Material Ontology
 Spatial/LIFE + Work Budget + Harness
                   ↓
                  P3
      controlled world integration
                   ↓
                 PH6
      promoted persistent individuals
```

## Операционный resolver

При продолжении ветки:

1. прочитать `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`;
2. выполнить `current_step`;
3. перед major stage перечитать fresh `origin/main` Project Control;
4. после acceptance перечитать roadmap;
5. не выполнять `BLOCKED`/`DEFERRED` stages;
6. не переносить runtime/foundation ownership в ECO.

## ECO.CONV0-A — Global Consumer Requirements

Статус: `EXECUTE_NOW / DESIGN_CONTRACT_ONLY`.

Цель: до freeze GLOBAL-P0 R3 сформулировать, что ecology **потребляет** от canonical foundations и что ecology **публикует** как derived/domain output, не создавая private substitutes.

Обязательные границы:

- `SD / Spatial Domain Fabric` — addressing/domain requirements;
- `TF / Time Fabric` — simulation-time/history requirements;
- `WQ / World Query Fabric` — environmental projection requirements;
- `MAT / Material Ontology` — substrate/material projection requirements;
- `LIFE / Promotion-Dormancy-Demotion` — aggregate ↔ promoted-individual lifecycle requirements;
- `WB / World Work Budget` — bounded ecology-work proposal requirements;
- `NX8` — population/domain truth vs individual replication boundary;
- `WT` — future cross-domain effect boundary only.

CONV0-A должен завершиться ownership/compatibility matrix и списком architecture gaps. Никакой production adapter не создаётся.

## ECO.CAL1 — Morphology Economics Calibration

Статус: `NEXT_AFTER_CONV0_A`.

Перед unrestricted morphology evolution требуется закрыть риск `PH3C_FULL_POOL_COMPACT_DOMINANCE`.

Не подгонять коэффициенты под красивый результат. Порядок:

`missing mechanism -> causal experiment -> calibration -> full-pool robustness`.

Первыми кандидатами на causal mechanisms остаются:

- neighbour/self shading;
- vertical light competition;
- crown overlap;
- root overlap / below-ground competition;
- size-dependent reproduction;
- dispersal benefit from height;
- long-lived structural payoff;
- disturbance resistance.

До CAL1 acceptance запрещено заявлять unrestricted morphology/species emergence.

## ECO.P2 — Dispersal / Recruitment / Biogeography

После CAL1:

- P2.1 Seed Dispersal Kernel;
- P2.2 Establishment / Recruitment;
- P2.3 Local Population Turnover;
- P2.4 Patch Colonization;
- P2.5 Disturbance + Recovery;
- P2.6 Long-Horizon Biogeography;
- P2.7 Speciation Candidate Diagnostics.

Цель: lineage divergence возникает из migration + environment + resource competition + history, а не из hardcoded biome/species placement.

## ECO.CONV0-B — Canonical Contract Freeze

Статус: `WAIT_CANONICAL_R3_FOUNDATION_CONTRACTS`.

После появления canonical R3/WQ/MAT/LIFE/WB contracts повторить compatibility review и привязать ECO-side requirements к реальным canonical interfaces.

До этого запрещено invent private production API только потому, что canonical API ещё не готов.

## ECO.P3 и PH6 — только после production foundations

Не начинать production world integration, persistent detailed plants или networked individual vegetation до появления canonical foundations:

- World Query Fabric / canonical environment contracts;
- Unified Material Ontology projection;
- Spatial Domain Fabric;
- Promotion/Dormancy/Demotion semantics;
- World Work Budget;
- authority/persistence/transport integration;
- fresh PC0/Harness-controlled runtime frontier.

После gates:

`ECO.P3 -> controlled world integration -> ECO.PH6 promoted persistent individuals`.

PH6 хранит detailed development/damage/pruning state только для promoted/interacted individuals; planet-wide individual GrowthGraph truth запрещён.

## Network convergence principle

Default:

`server ecology population/domain truth -> client deterministic derived representation`.

Индивидуальный network/persistent object появляется только через explicit promotion boundary при interaction/damage/ownership relevance.

## Главный порядок

1. `ECO.PH RESEARCH COMPLETE`.
2. `CONV0-A` — короткий global consumer-requirements pass.
3. `CAL1` — основная research-линия.
4. `CAL1 -> P2`.
5. Когда canonical R3/WQ/MAT/LIFE/WB готовы — `CONV0-B` compatibility/freeze.
6. Ждать production foundations/Harness frontier.
7. Только затем `P3 -> PH6`.

Старое линейное направление `PH5 -> PH6` запрещено.
