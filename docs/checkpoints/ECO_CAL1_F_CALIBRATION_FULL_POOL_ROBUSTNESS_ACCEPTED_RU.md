# ECO.CAL1-F — Calibration + Full-Pool Robustness — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `e5a42237d025ff0f0e28623b5f9461ed65149874`.

Accepted parent CAL1-E: `6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814`.

Canonical CAL1-F aggregate: `f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed`.

Classification: `ROBUST_UNITY_CALIBRATION`.

## Exact Windows evidence

Canonical environment:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
C:\Godot\lunar-world-eco-evolutionary-ecology
RUN_ECO_CAL1_F_TESTS.ps1
```

Observed canonical diagnostics:

```text
seed_signatures                    = 5
seed_multi_pareto                  = 1.000000
environment_pareto_signatures      = 2
density_monotonicity_violations    = 0
disturbance_survival_violations    = 0
disturbance_seed_violations        = 0
calibration_min_pareto_jaccard     = 1.000000000000
calibration_mean_pareto_jaccard    = 1.000000000000
calibration_pareto_signatures      = 2
resource_signatures                = 3
strategy_pool_contexts             = 20
pairwise_resource_contradictions   = 0
```

Acceptance test: `PASS (64 assertions)`.

Fresh-process replay A/B both reproduced exact aggregate `f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed` and classification `ROBUST_UNITY_CALIBRATION`.

## Decision

The explicit ±15% mechanism envelope did not change Pareto membership (`min/mean Jaccard = 1.0`) while the experiment still observed three distinct resource signatures. Therefore the robustness test is informative rather than trivially static: multi-objective ecological trade-offs are stable while resource ranking remains context-sensitive.

Five deterministic phenotype seeds produced five distinct signatures and retained multi-member Pareto fronts in 100% of seed contexts. Density and disturbance monotonicity had zero violations. Restricted strategy pools remained valid and pairwise/full-pool resource diagnostics had zero contradictions.

No coefficient movement is justified by current evidence. The accepted calibration remains the neutral UNITY profile:

```text
morphology_delta_multiplier = 1.0
vertical_light_multiplier    = 1.0
crown_overlap_multiplier     = 1.0
root_competition_multiplier  = 1.0
```

This is not an empirical botanical calibration; it is the accepted unmodified causal baseline after robustness screening.

## CAL1 closure

With CAL1-A through CAL1-F accepted, `ECO.EVO0 / Plant Causal Ecology Foundation` is complete.

The next executable checkpoint is:

`ECO.EVO1 / P2.1 Seed Dispersal Kernel`.

EVO1 must begin autonomous spatial state evolution; it must not regress to biome/species placement tables or presentation-as-truth.
