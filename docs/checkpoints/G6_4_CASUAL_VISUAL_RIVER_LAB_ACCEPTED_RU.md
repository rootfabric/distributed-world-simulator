# G6.4 Casual Visual River Lab — ACCEPTED

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Решение:** `ACCEPTED`

## Evidence

Windows Godot:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
G5 World Feature Graph                 PASS — 249
G5 feature/cell identity               PASS — 94
G6.0 fluid contracts                   PASS — 169
G6.1 CasualRiverProviderV1             PASS — 74
G6.2 cross-cell/cross-LOD continuity   PASS — 86
G6.3 runtime WaterSurfaceQuery         PASS — 79
G6.4 contracts                         PASS — 158
G6.4 Adaptive Macro Surface            PASS
far_lod -> near_lod                    1 -> 9
far_triangles -> near_triangles        120 -> 4176
octaves                                8
min_signal_km                          4.688
visual lab runtime marker              PASS
```

Manual graphical observation confirmed observer-driven refinement to approximately `LOD 10 @ 42.2 km`, subtle higher-frequency macro irregularities, continuous river presentation across the PX/PZ seam, and stable FeatureId / FluidRegionId.

Repository hygiene was rerun after documentation-only whitespace cleanup:

```text
git diff --check origin/feature/g5-world-feature-graph...HEAD
PASS
working tree CLEAN
```

No G6 runtime code changed after the successful Fix4 Windows runtime test. The cleanup was documentation-only.

## Architectural boundary

G6.4 remains derived presentation:

```text
G5 FeatureId
  -> G6 canonical fluid geography
  -> WaterSurfaceQuery
  -> G2 adaptive representation selection
  -> G3 diagnostic macro surface
  -> visual river lab
```

LOD, SurfaceCellKey, renderer state and diagnostic height exaggeration do not own canonical river identity.

River-valley carving, bank shaping and erosion remain deferred to `G8 Geomorphology`; layered subsurface geology remains `G9 Layered Geology`.

## Next checkpoint

`G6 FULL ACCEPTANCE` is already implemented but remains blocked by the shared MW10 baseline. PR #43 must first be integrated into `feature/g5-world-feature-graph`, then G6 must be resynchronized and `RUN_G6_FULL_ACCEPTANCE.ps1` rerun.
