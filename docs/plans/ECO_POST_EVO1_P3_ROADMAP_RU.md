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
P3.5 Seasonal World = IMPLEMENTATION CANDIDATE / targeted Linux PASS / canonical gate blocked on P3.4 ACCEPTED
P3.6 Disturbance & Succession = IMPLEMENTATION CANDIDATE / targeted Linux PASS / canonical gate blocked on P3.5 ACCEPTED
P3.7 Multi-Niche / Stable Coexistence = IMPLEMENTATION CANDIDATE / targeted Linux PASS / canonical gate blocked on P3.6 ACCEPTED
P3.8 Deterministic Ecosystem Persistence = IMPLEMENTATION CANDIDATE / targeted Linux PASS / canonical gate blocked on P3.7 ACCEPTED
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
-> run exact P3.5 Windows canonical gate
-> accept P3.5
-> open P3.6 Disturbance & Succession
```

P3.5 pre-acceptance implementation candidate now exists on top of the immutable P3.4 candidate identity. This does not promote P3.4 or P3.5.

P3.5 candidate contract:

```text
direct environment(time) evaluation from P3.4 baseline
finite period/epoch and continuous global phase
continuous x/y/altitude spatial phase shift
piecewise-linear triangle seasonal waveform; no sin/cos hash dependency
independent temperature/moisture/light/nutrient amplitudes and phase offsets
P3.4 bounds preserved
seasonal light/moisture/nutrients -> P3.1 resource-supply bridge
resource-mediated growth response without species-name winner table
P3.4 edge topology preserved with current seasonal environmental deltas
periodic patch state without cumulative timestep drift
negative-time deterministic wrap
no RNG
fail-closed malformed/tampered state
```

Targeted exact-Godot evidence:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.4 parent regression = PASS (56 assertions)
P3.5 fresh A/B/C = PASS (74 assertions each; byte-identical logs)
aggregate_hash=255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
phase0_hash=2ee8d7c6dc55a7c55af35cc945b0b85f79cc27fe0145b921eb5b9f0023b5d060
quarter_hash=3e9ae067e034b4a4ce4b149ee0306ecfae7d12189d82d55e6d2e5e541dab1bb2
half_hash=aec09a3a29d5c528140e70d79cd7970e3d3d09ee9e4f848d854cd205bc13b790
```

P3.5 remains canonical-gated on `P3.4 = ACCEPTED*`; its targeted pass does not authorize P3.6.

P3.6 pre-acceptance implementation candidate now exists, without opening P3.7 canonically. Contract: continuous heat/flood/drought pressure channels, functional resistance/recovery/pioneer traits, seasonal resource-limited recovery, bounded pre-disturbance biomass ceiling, direct no-drift recovery evaluation and no RNG.

Targeted exact-Godot evidence:

```text
P3.5 parent regression = PASS (74 assertions)
P3.6 fresh A/B/C = PASS (33 assertions each; byte-identical logs)
aggregate_hash=a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
```

P3.6 canonical runner remains blocked until `P3.5 = ACCEPTED*`.

P3.7 pre-acceptance implementation candidate now exists on top of the exact P3.6 candidate identity. It proves environment-differentiated niche targets, strict biomass conservation, negative frequency feedback, monotonic convergence to a multi-lineage fixed point and exact symmetry without ID-based winner selection.

Targeted exact-Godot evidence:

```text
P3.7 fresh A/B/C = PASS (64 assertions each; byte-identical logs)
aggregate_hash=ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
parent_p3_6=a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
```

P3.7 canonical runner remains blocked until `P3.6 = ACCEPTED*`.

P3.8 Deterministic Ecosystem Persistence implementation candidate now exists on the exact P3.7 candidate identity. It stores a validated typed current P3.7 state, which recursively retains P3.6/P3.5/P3.4/P3.3 state and P3.2 ancestry, inside a SHA-256 + exact-length checkpoint envelope.

Targeted exact-Godot evidence:

```text
P3.7 parent regression = PASS (64 assertions)
P3.8 fresh A/B/C = PASS (52 assertions each; byte-identical logs)
P3.8 cross-process writer/resume = PASS
aggregate_hash=6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
checkpoint_sha256=1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367
final_state_hash=1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9
```

P3 implementation sequence P3.1..P3.8 is now complete-as-candidate. Canonical P3 completion remains blocked until the exact Windows acceptance chain is advanced sequentially from P3.3 through P3.8.

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
