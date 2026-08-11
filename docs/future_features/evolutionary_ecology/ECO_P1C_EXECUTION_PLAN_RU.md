# ECO.P1C — Strategy Competition Proof — execution plan

Цель P1C: доказать, что несколько resource-paying ecological strategies могут устойчиво сосуществовать в heterogeneous world без predefined species/biome roles и без одного глобального optimum.

## P1C-S1 — Unlabeled Founder Pool + Shared-Field Competition Baseline

20 deterministic continuous founder genomes, общий competition field, uniform control, explicit P1A tradeoff probes. Это baseline, а не финальный coexistence proof.

## P1C-S2 — Dynamic Shared-Patch Abundance Competition

Перевести retained-set comparison в population frequencies/biomass through time. Competition update должен использовать accepted recruitment/biomass/resource consequences, а не новый hand-written fitness. Проверить dominance, turnover, extinction и persistence.

## P1C-S3 — Niche/Cluster Diagnostics + Multi-seed Coexistence

Post-hoc trait clustering без canonical species classes. Метрики: persistent clusters, Shannon diversity, dominance ratio, occupied niche volume, coexistence duration. Несколько seeds должны воспроизводить coexistence как явление, даже если конкретные clusters различаются.

## P1C-S4 — Robustness / PH convergence gate

Long run, neutral/homogeneous controls, failure matrix `99% dominance`, runaway traits, all-extinction, hardcoded region dependence. Если morphology входит в strategy space, перед финальным P1C acceptance требуется convergence с PH3 morphology-to-resource coupling; иначе P1C фиксируется как ecological-trait-only proof и morphology остаётся отдельным расширением.

Migration/dispersal biogeography остаётся вне P1C.
