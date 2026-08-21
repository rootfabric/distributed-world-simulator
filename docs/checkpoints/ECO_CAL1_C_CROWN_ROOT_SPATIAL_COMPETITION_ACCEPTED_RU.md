# ECO.CAL1-C — Crown + Root Spatial Competition — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `69910d1bd2ed7983df9c0d40213012a11dcb2f6a`.

Canonical gate executed on exact Windows checkout with Godot `4.7.1.stable.double.custom_build.a13da4feb`.

## Parent preservation

`ECO.CAL1-B` accepted aggregate remained exact:

`c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`.

The full parent chain PH3 -> PH3C -> CAL1-A -> CAL1-B passed before CAL1-C.

## Canonical CAL1-C evidence

Aggregate:

`d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`.

Fresh-process replay A/B reproduced the same aggregate exactly.

### Crown spatial competition

```text
close overlap = 2.009302166860 m2
far overlap   = 0.388093912912 m2

close focal loss = 0.047875621286
far focal loss   = 0.009247109521

high-branch neighbour loss = 0.066432935629
low-branch neighbour loss  = 0.014469693843
```

This proves that crown competition is controlled by actual pair geometry and neighbour canopy density rather than a static environment-only scalar.

No-overlap neutrality, distance monotonicity and A/B swap symmetry passed.

### Root spatial competition

```text
deep claim    = 0.820512820513
shallow claim = 0.179487179487
sum           = 1.0

root dense deep delta    = -0.000826156005
root dense shallow delta = -2.124931479778

root sparse deep delta    = -0.000142154530
root sparse shallow delta = -0.218000687034
```

The deep/shallow control proves differentiated claims in a shared root zone. Dense overlap causes a materially stronger resource effect than sparse overlap. Resource consequences are still evaluated through accepted P1 `plant_resource_model_v1.gd`; CAL1-C did not add a duplicate water/nutrient fitness model.

`root_zone_radius = root_depth` remains explicitly a CAL1-C research geometry proxy, not a canonical botanical law.

## Decision

`ECO_CAL1_C_ACCEPTED`.

CAL1-C closes the spatial competition hole for this research stage:

- crown competition depends on real spatial overlap;
- neighbour canopy density changes shading pressure;
- root competition depends on shared spatial resource zones;
- claims conserve one;
- dense/sparse context changes effect magnitude;
- accepted parents remain reproducible;
- no coefficient calibration was performed.

## Next

`ECO.CAL1-D — Lifetime / Reproduction / Dispersal / Disturbance Payoffs` is now unblocked.

CAL1-D must move selection away from a purely instantaneous resource view and prove separate causal paths for maturity, reproduction, release-height dispersal, longevity/structural amortization and disturbance survival/recovery.
