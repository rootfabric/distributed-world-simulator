# ECO.EVO1 / P2.5 — Disturbance + Recovery — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `b645ee451dd5c1c2558647c8e50eb293ec80c21c`.

Candidate/control head tested on Windows: `a40efb45437387812adbc6fdaac2a5ae494362e5`.

Parent: `ECO.EVO1/P2.4 ACCEPTED`, aggregate `78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97`.

Canonical Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Canonical P2.5 aggregate:

```text
292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
```

Fresh-process replay A/B reproduced the same aggregate exactly.

## Canonical evidence

```text
mild_loss              = 0.030140495868
severe_loss            = 0.073198347107
shallow_survival       = 0.297520661157
deep_survival          = 0.787500000000
mild_bank_killed       = 20
severe_bank_killed     = 70
severe_post_biomass    = 0.086801652893
single_severe_final    = 0.111289229748
recovery_gain          = 0.024487576856
reactivated            = 81
repeated_reactivated   = 79
repeated_final         = 0.076970584820
second_loss            = 0.037909682296
```

Acceptance test: `PASS (173 assertions)`.
Restart replay probe: `PASS (5 assertions)` in both fresh processes.
Parent P2.4 and all earlier accepted regressions remained PASS.

## Accepted semantics

P2.5 establishes explicit disturbance chronology without encoding species-specific disturbance outcomes.

Event pressure is represented by two independent research channels:

```text
mechanical_severity
seed_bank_mortality_fraction
```

Adult response delegates to accepted CAL1-D exposure/anchoring mechanics. Seed-bank damage uses exact integer conservation and rebuilds valid P2.2 cohorts. Recovery reuses P2.2 bank reactivation, P2.3 turnover coefficients, ResourceModel and accepted P1 patch capacity.

Observed causal directions are accepted:

- severe adult damage > mild adult damage;
- severe seed-bank kill > mild seed-bank kill;
- deep/anchored lineage survival > shallow lineage survival under the same event;
- surviving seed-bank memory reactivates (`81` recruits in the severe chronology);
- a single severe event shows positive multi-year recovery (`+0.024487576856` biomass);
- a second event causes additional damage (`0.037909682296`);
- repeated disturbance finishes below single-severe recovery (`0.076970584820 < 0.111289229748`);
- all adult and seed-bank event ledgers conserve;
- execution is deterministic across fresh processes.

## Ownership boundary

The event contract remains research input only. P2.5 does not claim canonical environment/weather event generation, Time Fabric, Spatial Domain Fabric, World Lifecycle, Work Budget, persistence, authority or network ownership.

## Implementation boundary

`122ed0c5f0f08ec36bd4fdec8fda8af1c9e9270b -> b645ee451dd5c1c2558647c8e50eb293ec80c21c` added exactly five P2.5 research/test files. Accepted P2.4-or-earlier source and runtime paths were not modified.

## Decision

```text
ECO.EVO1/P2.5 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P2.6 Long-Horizon Biogeography = EXECUTE_NOW
```
