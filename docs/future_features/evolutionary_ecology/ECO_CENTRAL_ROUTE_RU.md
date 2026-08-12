# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-E EXECUTE_NOW / NO CALIBRATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted chain

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED
ECO.CAL1-B                ACCEPTED
ECO.CAL1-C                ACCEPTED
ECO.CAL1-D                ACCEPTED
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`;
- CAL1-D `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`.

CAL1-D exact Windows evidence proved maturity/reserve reproduction gating, release-height dispersal, maturity timing, lifespan structural amortization, disturbance anchoring/survival and growth-rate recovery without a combined lifecycle-fitness scalar.

## Central route

```text
CAL1-A ACCEPTED
   ↓
CAL1-B ACCEPTED
   ↓
CAL1-C ACCEPTED
   ↓
CAL1-D ACCEPTED
   ↓
CAL1-E ← CURRENT
combined mechanism matrix / no calibration
   ↓
CAL1-F calibration + full-pool robustness
   ↓
EVO1 PLANT WORLD PROOF
```

## CAL1-E purpose

CAL1-E is the first integration checkpoint for the accepted causal layers. It must reveal interactions and trade-offs without hiding them inside a tuned scalar.

Matrix:

```text
8 morphology strategies
× 4 environments
× 2 density regimes
× 3 disturbance regimes
= 192 strategy-context rows
```

Environments: `REFERENCE`, `SHADE`, `SUN`, `DRY`.

Density: `SPARSE`, `DENSE`.

Disturbance: `NONE`, `MILD`, `SEVERE`.

### Resource ledger

Only quantities already expressed as resource/selection deltas are combined:

```text
accepted PH3 coupled resource balance
+ CAL1-B relative vertical-light delta
- CAL1-C crown-overlap loss
+ CAL1-C root-competition delta
= combined resource ledger
```

No new coefficients are introduced.

### Lifecycle vector

CAL1-D observables remain separate:

- maturity time;
- post-disturbance seed potential;
- effective seed dispersal;
- disturbance survival;
- recovery time;
- annual structural amortization.

CAL1-E must not add meters, seeds and resource balance with arbitrary weights.

### Comparison policy

Each context reports separate metric winners and a Pareto front across accepted objectives. A strategy is Pareto-dominated only if another strategy is no worse on every tracked objective and strictly better on at least one.

This is the no-calibration bridge from mechanism proofs to CAL1-F.

## CAL1-F boundary

CAL1-F remains the first checkpoint allowed to calibrate magnitudes and perform full-pool robustness across seeds, environments, density, disturbance, parameter perturbations and strategy-pool changes.

CAL1-E may diagnose dominance or missing interactions but must not tune them away.

## After CAL1

After CAL1-F acceptance the branch moves directly to `ECO.EVO1_PLANT_WORLD_PROOF`: autonomous spatial plant ecology with dispersal, recruitment, succession, disturbance/recovery, migration/isolation and lineage divergence. Presentation work remains secondary.

## Global boundary

Standalone EVO remains research-only. `XFER1/LIVE` wait for canonical simulator foundations. ECO does not create private global runtime foundations.

Current resolver: `EXECUTE CAL1-E COMBINED MECHANISM MATRIX WITHOUT CALIBRATION`.
