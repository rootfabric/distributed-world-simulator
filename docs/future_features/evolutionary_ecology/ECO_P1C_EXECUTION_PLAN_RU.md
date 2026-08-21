# ECO.P1C — Strategy Competition Proof — execution plan

Цель P1C: доказать, что несколько resource-paying ecological strategies могут устойчиво сосуществовать в heterogeneous world без predefined species/biome roles и без одного глобального optimum.

## P1C-S1 — Unlabeled Founder Pool + Shared-Field Competition Baseline — ACCEPTED

20 deterministic continuous founder genomes, общий competition field, uniform control, explicit P1A tradeoff probes. Windows: `116/116 + restart 5/5`.

## P1C-S2 — Dynamic Shared-Patch Abundance Competition — ACCEPTED

Retained-set comparison переведён в biomass/frequency dynamics through time. Competition использует accepted recruitment/biomass/resource consequences, а не новый hand-written fitness. Windows: `101/101 + restart 5/5`.

## P1C-S3 — Niche/Cluster Diagnostics + Multi-seed Coexistence — ACCEPTED

Post-hoc anonymous trait clustering без canonical species classes. Ниша требует environment-dependent regional enrichment; геометрического clustering недостаточно. Windows: heterogeneous `64/63/63`, uniform `64`, aggregate `5/5`, restart `5/5`.

## P1C-S4 — Competition Robustness + Aggregate Acceptance — CURRENT

Финальный falsification gate:

- шесть heterogeneous founder seeds;
- 18 abundance cycles;
- uniform negative control;
- 24-cycle deep horizon;
- explicit failure matrix: `GLOBAL_TAKEOVER`, `DIVERSITY_COLLAPSE`, `CLUSTER_COLLAPSE`, `FALSE_NICHE_UNIFORM`, `RUNAWAY_TRAIT`, `REPLAY_DIVERGENCE`;
- exact deterministic hashes + fresh-process replay.

P1C остаётся **ecological-trait-only proof**: morphology/development graph ещё не участвуют в competition state или resource equations. Поэтому PH3 convergence не является блокером текущего P1C aggregate acceptance. Если в будущем morphology войдёт в strategy/resource space, соответствующий morphology-aware gate должен пройти отдельную PH convergence проверку до принятия такой расширенной модели.

Migration/dispersal biogeography остаётся вне P1C.
