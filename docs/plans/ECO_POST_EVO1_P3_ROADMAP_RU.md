# ECO — Post-EVO1 P3 Research Roadmap

Статус: `ACTIVE RESEARCH ROUTE / POST-EVO1`.

Ветка: `feature/eco-evolutionary-ecology`.

Frozen foundation: `ECO.EVO1 COMPLETE`, final accepted P2.8 aggregate `ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6`.

Этот route продолжает ecology research новыми checkpoint'ами и не переопределяет accepted EVO1 semantics.

## Sequence

1. `P3.1 Resource Competition` — bounded shared light/water/nutrient pools, deterministic allocation, conservation, limiting-resource response, permutation independence.
2. `P3.2 Density & Carrying Capacity` — local biomass/density pressure, bounded carrying capacity, crowding costs and recovery without hard-coded winners.
3. `P3.3 Spatial Dispersal` — explicit local neighbourhoods and deterministic dispersal across patches/cells.
4. `P3.4 Environmental Gradient` — continuous temperature/moisture/light/nutrient/altitude-like gradients rather than fixed biome tables.
5. `P3.5 Seasonal World` — deterministic time-varying resource/environment cycles and life-history response.
6. `P3.6 Disturbance & Succession` — fire/flood/drought-like research disturbances plus recovery/succession dynamics.
7. `P3.7 Multi-Niche / Stable Coexistence` — demonstrate coexistence under differentiated resource/environment niches; no scripted winner.
8. `P3.8 Deterministic Ecosystem Persistence` — save/restart/fresh-process equivalence for the complete P3 state.

Each checkpoint follows:

```text
contract
-> deterministic model
-> focused acceptance test
-> parent regression
-> fresh process/repeat evidence
-> immutable hashes
-> ACCEPTED
```

## Current checkpoint state — 2026-08-13

```text
ECO.EVO1 / P2.8 = ACCEPTED
P3.1 Resource Competition = ACCEPTED / exact Windows canonical
P3.2 Density & Carrying Capacity = ACCEPTED / exact Windows canonical
P3.3 Spatial Dispersal = OPEN / implementation next
```

P3.1 exact Windows canonical aggregate:

```text
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

P3.2 exact Windows canonical evidence was captured from head `4ade178fc394cb5b220d206465310f06f63e4cfb` with Godot `4.7.1.stable.double.custom_build.a13da4feb`. Both canonical P3.2 processes matched:

```text
aggregate_hash=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
parent_p3_1=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

Evidence integrity:

```text
raw_log_sha256=a60db1644a45917c73d2eedaee9e244e33acd4fcbdcfd385a964e6798a4035eb
evidence_sha256=6619064b6770438c5d63661aff65c5a92dddc7740655f67b13644daa7ee98a26
```

P3.3 is therefore allowed to open. It must treat accepted P3.2 as immutable parent and add spatial topology/dispersal as a separate deterministic layer.

## P3.3 opening boundary

P3.3 should introduce explicit patch/cell identities and directed or undirected neighbourhood edges with deterministic canonical ordering. Dispersal must conserve transferred biomass/propagule mass within the modelled system unless an explicitly modelled boundary-export sink is present.

Required P3.3 properties include:

```text
accepted P3.2 parent pin
canonical patch order
canonical edge order
input permutation independence
no duplicate patch IDs / duplicate directed edges
bounded dispersal fractions
source export never exceeds available biomass
closed-system conservation
explicit boundary export accounting
no species-name / plant-id winner table
same input / fresh process -> same result_hash
tampered derived state -> validation FAIL
```

## Observer lane — low priority

`OBS1.1 Read-only Low-poly Observer` is implemented as a non-gating parallel lane with targeted Linux PASS and a successful interactive Windows launch. It remains presentation-only and does not change P3 acceptance state.

Current OBS1 surface:

```text
simple ground / patches
simple low-poly plant proxies
Play / Pause / Step
current year/step
resource pressure / limiting resource hints
population / biomass summary
```

Hard boundary:

```text
simulation state != visual state != network transport
```

OBS1 reads immutable/reproducible snapshots only. It does not mutate ecology state, consume simulation RNG, alter time stepping, persistence or acceptance hashes. Current proxy placement/palette is deterministic from canonical plant order and uses no randomness.

## Later integration boundary

Production integration remains separate from P3 research acceptance and must eventually prove deterministic region/chunk ownership, save/restore, catch-up and server handoff. The same ecological history must not depend on which server currently owns a region.
