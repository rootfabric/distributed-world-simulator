# G7.1 G3/G5/G6 Upstream Semantic Field Adapters — ACCEPTED

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**Tested runtime head:** `61de8526448a5a2ab95745fa380cdc8b3c4ea24f`
**Engine:** `4.7.1.stable.double.custom_build.a13da4feb`

## Decision

```text
G7.1 Upstream Semantic Field Adapters  ACCEPTED
```

Полный Windows gate завершён:

```text
G7.1 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-08-R1
G7.0 ACCEPTED ancestor: PASS
G7.1 adapter scope: PASS
G3/G5/G6 semantic adapters: PASS
World/core regression: PASS
Working tree: CLEAN
```

Также подтверждены:

```text
RL3 representation streaming processes PASS — 37 assertions
main_scene_cli_all                      PASS — 6 / 6
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Accepted projections

```text
G3 CasualMacroTerrainProviderV1
  -> geo/surface-height-m

G5 WorldFeatureGraph
  -> geo/valley-influence

G6 WaterSurfaceResolverV1
  -> geo/river-distance-m
  -> geo/river-width-m
  -> geo/fluid-surface-distance-m
```

Fix1 aligned the adapters with the exact accepted upstream contracts:

```text
GeoProvider result values      = details.values
WaterSurfaceSample river width = channel_width_m
```

Accepted blobs:

```text
G3 adapter  c728cfed5a2b3dd55d23b81b250177af19746623
G5 adapter  39ef95704cdf516b10146d2fa79b0d80bf173492
G6 adapter  437d82b7f056648045fff08f1daa57968331104c
G7.1 test   1af618356b700e5c87a55b42daa05d35b267014e
```

## Ownership

G7.1 is a projection layer only.

```text
ProviderId      remains G3/G4-owned
FeatureId       remains G5-owned
FluidRegionId   remains G6-owned
Geomorphology   remains future G8-owned
Material truth  remains P0 Material Ontology-owned
Authority       not owned by G7
Persistence     not owned by G7
Network         not owned by G7
Scheduler/cache not owned by G7
```

No new River, Feature or FluidRegion identity is created by the semantic adapters.

## Next

```text
G7.2 — Composition / Provenance
```

G7.2 may compose the accepted partial samples into a deterministic semantic bundle and an auditable composition receipt. It must not become a scheduler/cache, WorldQuery, authority or persistence foundation.
