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
P3.3 Spatial Dispersal = CANDIDATE / targeted Linux PASS / exact Windows canonical pending
P3.4 Environmental Gradient = IMPLEMENTATION CANDIDATE / targeted Linux PASS / canonical gate blocked on P3.3 ACCEPTED
```

Accepted P3.2 aggregate:

```text
172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

P3.3 treats this as immutable parent and operates on P3.2 `next_biomass_kg` results without changing P3.2 semantics.

P3.3 current research contract:

```text
explicit patch/cell IDs
unique directed neighbour edges
canonical patch + edge ordering
relative edge weights normalized per source
bounded global dispersal fraction
bounded explicit boundary-export fraction per patch
isolated internal dispersal retained rather than destroyed
incoming transfer may colonize a destination patch
closed-system biomass conservation
explicit outside-system export accounting
no simulation RNG
no plant/species winner table
```

Targeted evidence using the attached exact Godot build:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.2 parent regression = PASS (79 assertions)
P3.3 fresh A/B/C = PASS (66 assertions each)
aggregate_hash=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
network_hash=21a8de4b12cd541d40c8fd34b725e59e493a775e3465b853945f46f85445a8a2
closed_hash=039fb7fc353e36f4d0d42fa146760062704e91a6ed21c03bff8213feec96cc5f
isolated_hash=14d1d467d65047e362fc6bd04dd668ab1713d986c1bb97f79734ecc0370441ec
```

P3.3 canonical acceptance order:

```text
P3.2 = ACCEPTED
-> run exact P3.3 Windows canonical gate
-> accept P3.3
-> open P3.4 Environmental Gradient
```

P3.4 canonical lifecycle remains closed until P3.3 is canonically accepted. A pre-acceptance implementation candidate now exists so development can continue without falsifying the parent gate.

P3.4 candidate contract:

```text
explicit x/y/altitude coordinate per P3.3 patch
continuous affine temperature/moisture/light/nutrient fields
configurable origin and per-channel x/y/altitude slopes
normalized moisture/light/nutrient bounds in [0,1]
no biome enum/table or threshold ownership
resource availability bridge: light->light, moisture->water, nutrients->nutrients
P3.3 edge environmental delta diagnostics
coordinate permutation independence
no RNG
fail-closed malformed/tampered state
```

Targeted exact-Godot evidence:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.3 parent regression = PASS (66 assertions)
P3.4 fresh A/B/C = PASS (56 assertions each; byte-identical logs)
aggregate_hash=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
gradient_hash=2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293
```

Strict acceptance order is still:

```text
accept P3.3
-> run exact P3.4 Windows canonical gate
-> accept P3.4
-> open P3.5 Seasonal World
```

## Observer lane — low priority

`OBS1.1 Read-only Low-poly Observer` is implemented as a non-gating single-patch viewer with targeted Linux PASS and a successful interactive Windows launch.

`OBS1.2 Read-only Spatial Ecology Observer` is now implemented as a non-gating P3.3 viewer. It renders deterministic multi-patch tiles, plant proxies and directed transfer flows only from defensive P3.3 snapshots. Targeted exact-Godot evidence: `PASS (47 assertions)` in three byte-identical fresh processes plus `Spatial Scene Smoke: PASS (12 assertions)` with no Godot `ERROR:` lines.

OBS1.2 snapshot arithmetic independently reconciles patch source/incoming/final biomass, edge transfers, outgoing shares, explicit boundary export and global conservation. Observer code does not own graph topology, transfer decisions, simulation RNG or canonical hashes.

Hard boundary:

```text
simulation state != visual state != network transport
```

## Later integration boundary

Production integration remains separate from P3 research acceptance and must eventually prove deterministic region/chunk ownership, save/restore, catch-up and server handoff. The same ecological history must not depend on which server currently owns a region.
