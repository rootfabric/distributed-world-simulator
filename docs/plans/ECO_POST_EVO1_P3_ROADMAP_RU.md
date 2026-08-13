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
P3.1 Resource Competition = CANDIDATE / targeted Linux PASS / exact Windows canonical pending
P3.2 Density & Carrying Capacity = CANDIDATE / targeted Linux PASS / blocked on P3.1 ACCEPTED + exact Windows canonical
P3.3 = NOT OPENED
```

P3.2 introduces a soft resource-coupled carrying-capacity response rather than reusing older hard proportional patch clipping. Its canonical runner intentionally fails closed while P3.1 factual validation status is not `ACCEPTED*`.

Acceptance order is therefore strict:

```text
accept P3.1
-> run exact P3.2 canonical gate
-> accept P3.2
-> open P3.3
```

## Observer lane — low priority

After P3.2, a small `OBS1` may be implemented in parallel as a non-gating, casual low-poly observer:

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

OBS1 reads immutable/reproducible snapshots only. It must not mutate ecology state, consume simulation RNG, alter time stepping, persistence or acceptance hashes. Visual randomness, if any, uses a renderer-only seed derived from already frozen state.

## Later integration boundary

Production integration remains separate from P3 research acceptance and must eventually prove deterministic region/chunk ownership, save/restore, catch-up and server handoff. The same ecological history must not depend on which server currently owns a region.
