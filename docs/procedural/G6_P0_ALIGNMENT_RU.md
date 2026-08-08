# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Current stage:** `G6.4 Casual Visual River Lab — FIX3 IMPLEMENTED CANDIDATE`
**Next after acceptance:** `G6 FULL ACCEPTANCE`

## Canonical boundary

```text
G5 WorldFeature / FeatureId
        ↓
G6.1 canonical fluid geography
        ↓
G6.3 read-only WaterSurfaceQuery resolver
        ↓
G6.4 derived presentation
```

Fix3 composes accepted G2/G3 only in representation:

```text
observer
  -> G2 SurfaceLodSelector
  -> adaptive SurfaceCellKey leaves
  -> G3 CasualMacroTerrainProviderV1
  -> geo/surface-height-m samples
  -> adaptive terrain triangles
```

Required invariants:

```text
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
LOD != fluid identity
terrain mesh != canonical G3 height field
visual height exaggeration != canonical height
renderer != authority
renderer != persistence
G5 River FeatureId remains semantic owner
```

## Why Fix3

Fix2 automated gate passed and the manual run proved that `SurfaceLodSelector` refines the cover. But a smaller grid alone did not reveal new world detail because the visible globe remained a fixed `SphereMesh` and denser river samples stayed on the same smooth spline.

Fix3 therefore hides the fixed sphere and rebuilds the visible surface from the selected leaves. Every new terrain vertex samples accepted G3 `geo/surface-height-m` in body-fixed direction space. Near views have more actual triangles and can expose more of the continuous G3 macro field.

The x40 height multiplier is explicitly display-only. It exists only because a 900 m relief is otherwise almost invisible on an 8-unit debug globe.

## No premature geomorphology

G6.4 still does not alter terrain from hydrology:

```text
river does NOT carve a valley
river does NOT rewrite G3 height
water ribbon does NOT own terrain
```

River/terrain causal shaping remains `G8 Geomorphology`; layered subsurface materials remain `G9 Layered Geology`.

## GLOBAL-P0 synchronization

The checkpoint remains on `GLOBAL-P0-2026-08-08-R1`. G6 is currently not behind `feature/g5-world-feature-graph`. Before full G6 acceptance, main/G5/shared baseline must be checked again for the MW10 integration or a newer global revision.

## Accepted foundation

```text
G6.1 CasualRiverProviderV1             ACCEPTED — 74 assertions
G6.2 cross-cell/cross-LOD continuity   ACCEPTED — 86 assertions
G6.3 runtime WaterSurfaceQuery         ACCEPTED — 79 assertions
```

## Fix3 proof requirements

Automated scene output must include:

```text
G6.4 Adaptive Macro Surface: PASS (... far_triangles=... near_triangles=...)
G6.4 Casual Visual River Lab: PASS (...)
```

and prove:

```text
near max_lod > far max_lod
near macro terrain triangles > far macro terrain triangles
near selection_hash != far selection_hash
```

Manual acceptance must show visible macro-surface refinement with `W/S`, while FeatureId/FluidRegionId remain stable and PX/PZ river continuity remains intact.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 checkpoint
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 Windows runtime query acceptance — 79 assertions
[PASS] G6.4 fix3 changes representation only
[PENDING WINDOWS] G6.4 fix3 source/headless macro-surface gate
[PENDING MANUAL] G6.4 graphical macro-surface refinement observation
[PENDING FULL G6] fresh main + G5/shared-baseline sync check, then full world/core regression
```
