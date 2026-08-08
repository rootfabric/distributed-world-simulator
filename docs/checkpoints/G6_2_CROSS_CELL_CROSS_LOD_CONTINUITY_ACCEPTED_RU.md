# G6.2 — Cross-cell / Cross-LOD Continuity — ACCEPTED

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependency:** `G6.1 CasualRiverProviderV1 — ACCEPTED`
**Implementation candidate:** `322265247bb0a01bf7bdd814adca2ead30b124c9`
**Fix1 code head:** `a3efb5dd314ef6c2e7d3b5d75d118402e7b45117`
**Tested head:** `444811c0ac98a133844cd7ec0869a6cf0a261f11`
**Решение:** `ACCEPTED`

## Что принято

G6.2 доказал, что canonical river geography не зависит от текущего разбиения на G2 `SurfaceCellKey` и LOD.

```text
G5 River FeatureId
        ↓
G6.1 CasualRiverProviderV1
        ↓
FluidRegionId / RiverSpline / ChannelProfile / FluidSurface
        ↓
G2 CubeSphereAddressing
        ↓
LOD-specific representation cells
```

Каноническая river/fluid identity остаётся выше representation topology.

## Continuity fixture

```text
planet radius:       6,000,000 m
source longitude:    34°
mouth longitude:     58°
expected cube faces: PX / PZ
LOD matrix:          2 / 4 / 8 / 12
```

На разных LOD representation cell sets реально меняются, но канонические значения остаются стабильными:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
provider manifest hash
RiverSpline checksum
FluidSurfaceDescriptor checksum
```

Это фиксирует архитектурный принцип:

```text
canonical river -> representation cells

NOT

representation cells -> river identity
```

## Первый Windows run и Fix1

Первый Windows focused run дал `85/86` assertions. Единственный failure был в manifest meta-check `G6.2 LOD proof levels pinned`.

Причина не относилась к hydrology continuity: JSON numeric values после `JSON.parse_string()` сравнивались напрямую с типизированным `Array[int]`. Manifest уже содержал корректные `[2, 4, 8, 12]`.

Fix1 нормализовал parsed LOD values через `int(...)` перед сравнением. Одновременно был устранён trailing whitespace в candidate checkpoint, найденный `git diff --check`.

Fix1 не менял:

```text
CasualRiverProviderV1
G6.0 fluid contracts
fixture geography
FeatureId / FluidRegionId semantics
SurfaceCellKey
CubeSphereAddressing
production runtime
network / authority / persistence
```

## Accepted Windows evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Focused chain:

```text
G5 World Feature Graph: PASS (249 assertions)
G5 feature/cell identity: PASS (94 assertions)
G6.0 fluid contracts: PASS (169 assertions)
G6.1 CasualRiverProviderV1: PASS (74 assertions)
G6.2 cross-cell/cross-LOD continuity: PASS (86 assertions)
G6.2 cross-cell/cross-LOD continuity focused gate passed.
```

Repository hygiene on tested checkout:

```text
working tree: clean
git diff --check e42954a47400b62a393d5447782eac2678d55295...HEAD: PASS
```

## Architecture result

G6.2 confirms:

```text
Feature != SurfaceCell
FluidRegion != SurfaceCell
LOD != river identity
CubeSphere face != river identity
RiverChunkId is not required
```

No new runtime query resolver, renderer, authority registry, persistence owner, or network transport was introduced.

## Next

```text
G6.3 — Runtime WaterSurfaceQuery Resolver
```

G6.3 may now consume the accepted canonical G6 geography and answer spatial fluid queries without requiring the caller to know `SurfaceCellKey`, cube face, or LOD.

Full world/core regression remains deferred to the composed G6.1–G6.4 final G6 acceptance unless G6.3 changes shared accepted runtime/contracts.
