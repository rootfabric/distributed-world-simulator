# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-F EXECUTE_NOW / ROBUSTNESS CLOSURE`.

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
ECO.CAL1-E                ACCEPTED
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`;
- CAL1-D `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`;
- CAL1-E `6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814`.

## CAL1-E accepted finding

The exact Windows combined matrix contains `192` rows / `24` contexts. All `96` sparse rows have zero neighbour interaction; all `96` dense rows activate neighbour mechanisms. All `24` contexts are multi-objective and all `24` have multi-member Pareto fronts; there are `2` distinct Pareto signatures.

In `REFERENCE/DENSE/NONE`, the Pareto front is:

```text
HEIGHT_LOW
HEIGHT_HIGH
BRANCH_LOW
GIANT_DENSE
```

`HEIGHT_LOW` wins combined resource and seed potential there, while `GIANT_DENSE` wins dispersal. This is evidence that expensive morphology has a causal payoff path and that the repaired model did not merely replace one universal winner with another.

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
CAL1-E ACCEPTED
   ↓
CAL1-F ← CURRENT
calibration + full-pool robustness
   ↓
CAL1 ACCEPTED / EVO0 CAUSAL FOUNDATION COMPLETE
   ↓
EVO1 PLANT WORLD PROOF
```

## CAL1-F policy

CAL1-F is the first stage allowed to calibrate magnitudes, but calibration is constrained:

- accepted A-E source files remain immutable;
- any new multiplier is explicit and lives only in a CAL1-F calibration profile;
- baseline multiplier vector is `1.0` for every accepted mechanism;
- perturbations test robustness around the accepted baseline; they are not used to force a desired winner;
- if conclusions are fragile, CAL1-F must report fragility rather than silently tune it away.

Required robustness dimensions:

```text
multiple deterministic phenotype seeds
environment perturbations
density perturbations
disturbance perturbations
mechanism-magnitude perturbations
strategy-pool composition changes
restart determinism
pairwise-vs-full-pool consistency diagnostics
```

The target is not artificial coexistence. Some strategies may lose almost everywhere. The target is that conclusions are not artifacts of a known missing mechanism, one exact coefficient value, one seed, one density, or one pool composition.

## CAL1-F acceptance meaning

CAL1 can close when the robustness sweep supports the statement:

> morphology economics now includes the major accepted causal benefit/cost paths needed for unrestricted morphology search, and observed dominance/trade-off patterns are reproducible under reasonable perturbations rather than being a fragile numerical artifact.

After CAL1 closure the branch must move to `ECO.EVO1 Plant World Proof`, not to additional presentation work.

## Global boundary

Standalone EVO remains research-only. `XFER1/LIVE` wait for canonical simulator foundations. ECO does not create private global runtime foundations.

Current resolver: `EXECUTE ECO.CAL1-F CALIBRATION + FULL-POOL ROBUSTNESS`.
