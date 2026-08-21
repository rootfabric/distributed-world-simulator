# ECO.EVO1 / P2.1 — Seed Dispersal Kernel — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `5a325549dd2b8bca64437fd42c549d798e7e3905`.

Canonical parent: `ECO.CAL1-F`, aggregate `f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed`, classification `ROBUST_UNITY_CALIBRATION`.

## Canonical evidence

Exact environment:

`Godot 4.7.1.stable.double.custom_build.a13da4feb` on the Windows branch checkout.

Result:

```text
ECO.EVO1-P2.1 Seed Dispersal Kernel: PASS (811 assertions)
aggregate_hash=cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
CAL1-F parent=f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
```

Fresh-process replay A and B reproduced the exact same aggregate hash.

Controlled evidence:

```text
distance_ratio       = 6.000000000000
release_ratio        = 2.000000000000
east_low             = 15.180360007930
east_high            = 5.205483576745
west_x               = -15.505240296661
boundary_outside     = 80
local                = 70
long_tail            = 10
event_hashes_differ  = true
```

## Accepted semantics

P2.1 establishes deterministic, lineage-preserving **seed cohort packet transport** as EVO1 truth. One reproduction event is represented by a bounded packet set rather than one entity per seed.

Accepted invariants:

- emitted seed counts are exactly conserved;
- `inside + outside = transported = emitted`;
- `local + long_tail = emitted`;
- outside-domain packets remain explicit transport output rather than being destroyed;
- lineage id, genome checksum and reproduction event remain attached to every packet;
- inherited `seed_dispersal_distance_m` scales transport distance causally;
- accepted CAL1-D release-height scaling is preserved: distance is proportional to `sqrt(release_height)`;
- dimensionless transport context creates directional anisotropy;
- greater turbulence weakens matched directional bias;
- different reproduction events create different deterministic spatial realizations;
- exact replay is stable across fresh Godot processes;
- no biome/species placement table is used.

## P2.2 boundary

P2.1 remains transport-only. It does not decide germination, establishment, seed-bank persistence, recruitment mortality, carrying capacity or local population turnover.

Those semantics are now unlocked for:

`ECO.EVO1 / P2.2 Establishment / Recruitment / Seed Bank`.

## Decision

`ECO_EVO1_P2_1_ACCEPTED`.

Next executable checkpoint: `ECO.EVO1 / P2.2`.
