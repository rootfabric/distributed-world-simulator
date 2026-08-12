# ECO.CAL1-F — Calibration + Full-Pool Robustness — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `e5a42237d025ff0f0e28623b5f9461ed65149874`.

Parent: `ECO.CAL1-E ACCEPTED`, aggregate `6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814`.

## Purpose

CAL1-F is the final EVO0/CAL1 checkpoint. It tests whether the accepted A-E causal model is robust to reasonable perturbations rather than being dependent on one exact seed, environment, density, disturbance, mechanism magnitude or strategy-pool composition.

It must not tune coefficients to make a preferred morphology win.

## Calibration policy

Without an external empirical target, the only defensible selected calibration is the accepted neutral baseline:

```text
UNITY:
morphology_delta_multiplier = 1.0
vertical_light_multiplier = 1.0
crown_overlap_loss_multiplier = 1.0
root_competition_multiplier = 1.0
```

CAL1-F then tests a symmetric `±15%` envelope:

- morphology low/high;
- vertical-light low/high;
- spatial crown/root low/high;
- all channels low/high.

If the model is robust, `UNITY` remains selected. If the envelope exposes fragility, the gate fails and reports it; CAL1-F must not silently tune it away.

## Robustness sweeps

### Deterministic phenotype seeds

Five deterministic seeds are used. Seed `0` reuses the accepted PH3C/CAL1-E reproduction event exactly; seeds `1..4` use distinct deterministic CAL1-F reproduction events.

The seed sweep covers:

```text
5 seeds × 4 environments × {NONE, SEVERE} × 8 strategies
= 320 rows / 40 contexts
```

### Environment perturbations

For every accepted environment, CAL1-F evaluates:

- BASE;
- moisture -10%;
- moisture +10%;
- sunlight -10%;
- sunlight +10%.

Total: `20 contexts / 160 rows`.

### Density perturbations

Controlled sequence:

```text
0.50 m @ density 1.00
0.75 m @ density 0.90
1.00 m @ density 0.75
1.50 m @ density 0.50
50.0 m @ density 0.15
```

For every strategy/environment the absolute accepted neighbour-interaction magnitude must not increase as distance grows and density falls.

Total: `20 contexts / 160 rows`.

### Disturbance perturbations

Severity sequence:

```text
0.00 / 0.10 / 0.20 / 0.50 / 0.90
```

Matched survival and post-disturbance seed potential must be non-increasing with severity.

Total: `20 contexts / 160 rows`.

### Mechanism magnitude envelope

Nine explicit calibration profiles are run over eight representative full-pool contexts (`4 environments × NONE/SEVERE`).

Total: `72 contexts / 576 rows`.

The UNITY recomposition must numerically reproduce accepted CAL1-E row metrics exactly. Perturbed Pareto fronts are compared to UNITY by Jaccard overlap.

Candidate robustness thresholds:

```text
minimum Pareto Jaccard >= 0.25
mean Pareto Jaccard    >= 0.50
```

These thresholds reject a completely different regime under a small ±15% perturbation while allowing real rank/Pareto movement.

### Strategy-pool composition

Five pools are tested in all four environments:

- FULL_8;
- NO_HEIGHT_LOW;
- NO_GIANT;
- CORE_5;
- ALTERNATE_5.

Every pool must retain a valid Pareto front. Removing `HEIGHT_LOW` must produce a deterministic fallback resource winner rather than breaking the model.

A resource-ledger pairwise/full-pool consistency diagnostic must report zero contradictions.

## Acceptance classification

CAL1-F accepts only as:

`ROBUST_UNITY_CALIBRATION`.

Required gates include:

- exact CAL1-E parent preservation;
- seed variation is real and deterministic;
- at least 75% of seed contexts retain multi-member Pareto fronts;
- environment sweep retains at least two Pareto signatures;
- zero density monotonicity violations;
- zero disturbance monotonicity violations;
- UNITY exactly reproduces CAL1-E metrics;
- calibration-envelope Pareto overlap meets thresholds;
- all pool variants have non-empty Pareto fronts;
- zero pairwise/full-pool resource contradictions;
- same-process and fresh-process aggregate equality.

## Implementation boundary

`c396561fc77f2c9c31dd00cd8c3f1bdd8822da10 -> e5a42237d025ff0f0e28623b5f9461ed65149874` adds exactly five ECO files:

- `scripts/research/ecology/plant_cal1_f_calibration_profile_v1.gd`;
- `scripts/research/ecology/plant_cal1_f_full_pool_robustness_v1.gd`;
- `tests/research/ecology/eco_cal1_f_full_pool_robustness_acceptance.gd`;
- `tests/research/ecology/eco_cal1_f_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_F_TESTS.ps1`.

Accepted A-E source files and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_F_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
CAL1-F = IMPLEMENTED_CANDIDATE
CAL1-F != ACCEPTED
EVO1 = BLOCKED
```

If the gate passes, CAL1 closes and the next executable milestone becomes `ECO.EVO1 / P2.1 Seed Dispersal Kernel` inside the Autonomous Plant World Proof.
