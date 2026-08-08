# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G3 ACCEPTED
G4 ACCEPTED — Architecture Review A PASS
G5 ACCEPTED
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED
G6.4 IMPLEMENTED CANDIDATE — Casual Visual River Lab
G6 FULL ACCEPTANCE NEXT after G6.4
```

Global revision:

```text
GLOBAL-P0-2026-08-08-R1
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_4_CASUAL_VISUAL_RIVER_LAB_CANDIDATE_RU.md`
3. `docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_ACCEPTED_RU.md`
4. `docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md`
5. `docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md`
6. `docs/procedural/G6_P0_ALIGNMENT_RU.md`
7. `docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md`
8. `docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md`
9. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
10. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`

## Current architecture

```text
G0 contracts / GeoKernel
        ↓
G1 body-fixed geodesy
        ↓
G2 cube-sphere cells + LOD
        ↓
G3 canonical macro surface
        ↓
G4 recipe-driven provider composition
        ↓
G5 canonical World Feature Graph
        ↓
G6.0 canonical fluid contracts
        ↓
G6.1 deterministic river provider
        ↓
G6.2 cross-cell/cross-LOD continuity — ACCEPTED
        ↓
G6.3 runtime WaterSurfaceQuery — ACCEPTED
        ↓
G6.4 replaceable visual river lab — CANDIDATE
        ↓
G6 full acceptance
        ↓
G7 Semantic Field Fabric
```

Accepted rule:

```text
G5 FeatureId = semantic river owner
G6.1 provider = canonical geography compiler
G6.2 cell/LOD = representation addressing only
G6.3 query resolver = read-only derived world service
G6.4 mesh/debug lab = replaceable presentation only
```

## G6.4 manual visual checkpoint

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Manual launch after automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Controls:

```text
A/D orbit     Q/E pitch     W/S zoom
Space auto-orbit            R reset
1 water       2 centerline  3 banks
4 probes      5 seam
```

The scene displays a planet-scale derived water ribbon, canonical centerline, bank guides, G6.3 query normal/flow probes and the `PX/PZ` cube-face transition marker. Water/bank width is deliberately exaggerated only in display space.

G6.4 is not accepted until both automated Windows validation and graphical manual observation pass.

## Synchronization note

`GLOBAL-P0-2026-08-08-R1` still matches main at implementation start. A fresh G5 shared-baseline PR #43 exists for the MW10 atomic-lock fix and is still open. G6.4 is presentation-only and does not depend on Matter, but full G6 acceptance must synchronize with the shared baseline if that fix lands before the final gate.

## Detail / asset doctrine

```text
BASE FIRST
BEAUTY SECOND
```

Photoreal water, foam, FFT waves and production shoreline remain deferred. The current visual lab exists to prove replaceable presentation over stable canonical/query contracts.
