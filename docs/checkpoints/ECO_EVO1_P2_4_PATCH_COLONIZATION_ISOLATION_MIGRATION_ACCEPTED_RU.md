# ECO.EVO1 / P2.4 — Patch Colonization / Isolation / Migration — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `01042d585fa46aebe5fde090e217c9fcb58be68f`.

Parent: `ECO.EVO1/P2.3 ACCEPTED`, aggregate `15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e`.

Canonical exact Windows environment:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Canonical aggregate:

```text
78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97
```

## Accepted evidence

```text
near_arrived=800
far_arrived=160
near_recruited=430
far_recruited=87
near_short=84
near_long=346
far_short=0
far_long=87
near_long_share=0.804651162791
far_long_share=1.000000000000
near_lineages=2
far_lineages=1
west_routed=0
```

Acceptance test: `PASS (28 assertions)`.

Fresh-process replay A/B both reproduced the exact aggregate `78273550...`.

## Meaning

P2.4 converts P2.1 outside-domain propagule packets into explicit research-scale inter-patch routing using their actual `destination_position`. Routing is spatial and causal; no biome/species placement table or generic migration score participates.

The controlled isolation experiment uses otherwise matched lineages differing only in inherited dispersal distance (`5 m` vs `20 m`). The near patch recruits both lineages while the far patch recruits only the long-disperser. Reversing transport westward routes zero seeds into the east-side targets.

Integer conservation remains exact across source retention, known-patch routing, unresolved export, and target P2.2 settlement.

Research patch `Rect2` geometry remains an experiment input only and does not claim canonical Spatial Domain Fabric ownership.

## Implementation boundary

`89aec8f317d8046f86369510e5d685fd6a8f2b06 -> 01042d585fa46aebe5fde090e217c9fcb58be68f` adds exactly five P2.4 research/test files. Accepted P2.3-or-earlier source and runtime paths are unchanged.

## Decision

```text
ECO.EVO1/P2.4 = ACCEPTED_EXACT_WINDOWS_CANONICAL
ECO.EVO1/P2.5 = EXECUTE_NOW
```

Next: `P2.5 Disturbance + Recovery`.