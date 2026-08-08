# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/g6-hydrology-fluid-surface-v0`  
**Current stage:** `G6 FULL ACCEPTANCE — IMPLEMENTED CANDIDATE / SHARED BASELINE BLOCKED`  
**Next after acceptance:** `G7 Semantic Field Fabric`

## Canonical boundary

```text
G5 WorldFeature / FeatureId
        ↓
G6.1 canonical fluid geography
        ↓
G6.3 read-only WaterSurfaceQuery resolver
        ↓
G6.4 replaceable derived presentation
```

G6.4 consumes accepted G2/G3 only as representation:

```text
observer
  -> G2 SurfaceLodSelector
  -> adaptive SurfaceCellKey leaves
  -> accepted G3 CasualMacroTerrainProviderV1
  -> derived terrain triangles

accepted G6 river/query truth
  -> derived adaptive water ribbon
```

Required invariants remain:

```text
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
LOD != fluid identity
terrain mesh != canonical G3 height field
visual detail recipe != canonical identity
renderer != authority
renderer != persistence
G5 River FeatureId remains semantic owner
```

## G6.4 Fix4 manual evidence

The Fix4 lab keeps accepted G3 provider code unchanged and uses a diagnostic 8-octave recipe down to about `4.6875 km` source wavelength. Manual observation confirmed refinement from roughly `LOD 6 @ 812.7 km` to `LOD 10 @ 42.2 km` and subtle newly visible macro irregularities. River presentation and canonical IDs stayed stable.

This is sufficient manual presentation evidence. The remaining Fix4 automated rerun is included in the full G6 runner.

## No premature geomorphology

G6 still does not make hydrology authoritative over terrain:

```text
river does NOT carve a valley
river does NOT rewrite G3 height
water ribbon does NOT own terrain
```

River/terrain causal shaping remains `G8 Geomorphology`; layered subsurface materials remain `G9 Layered Geology`.

## Full acceptance / synchronization gate

Entrypoint:

```powershell
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

It requires:

```text
GLOBAL config == main == G5
current G5 is ancestor of G6
accepted MW10 atomic-lock blobs are present in G5
same MW10 blobs are present in G6 after resync
git diff --check G5...G6
G6.0-G6.4 focused chain PASS
MW10 lock-release retry PASS
full world/core regression PASS
clean worktree
```

The MW10 requirement is deliberate P0 ownership hygiene. PR #43 is currently open and not merged into G5. G6 must not privately absorb that shared-baseline fix; it waits for G5 integration and then resynchronizes.

## Accepted foundation

```text
G6.1 CasualRiverProviderV1             ACCEPTED — 74 assertions
G6.2 cross-cell/cross-LOD continuity   ACCEPTED — 86 assertions
G6.3 runtime WaterSurfaceQuery         ACCEPTED — 79 assertions
G6.4 manual graphical evidence         PASS — Fix4
```

## Status dimensions

A green full gate will establish `G6 SOURCE_ACCEPTED`. It does not by itself claim:

```text
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

Those remain distinct according to GLOBAL-P0.
