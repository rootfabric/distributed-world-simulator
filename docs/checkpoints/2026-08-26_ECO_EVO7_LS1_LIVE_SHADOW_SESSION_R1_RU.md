# ECO.EVO7 LS1 — Live Shadow Evolution Session R1 — CANDIDATE

LS1 связывает EVO7 с реальным `ProceduralEarthWorld` как RAM-only эволюционную сессию.

- 3 live land sample внутри детерминированного регионального сектора Земли;
- 12 founder lineages с одинаковым исходным genome/traits;
- одна и та же exact founder population копируется во все 3 зоны;
- каждый цикл: live Earth observation → EVO7 phenotype/water-limited fitness → deterministic selection;
- offspring создаются **только** через `LineageExtension.reproduce_bundle` → canonical `plant_mutation_lineage_kernel_v1.reproduce`;
- mutation seed не содержит zone/moisture/light/water identity;
- evolution OFF сохраняет exact bundle identities;
- reset same seed восстанавливает исходный pool;
- world/ecology/persistence/network/XFER writes отсутствуют и fail-closed.

Это research/integration shadow checkpoint. Он не является FFF7/XFER acceptance, не даёт production ECO authority и не заменяет fresh Reviewer/Verifier chain.
