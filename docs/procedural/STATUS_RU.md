# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 Shared Baseline              ACCEPTED
G6 Full Acceptance                     READY FOR FULL WINDOWS GATE
```

G6.4 remains accepted from Windows Godot 4.7.1 double evidence:

```text
G6.4 contracts                           PASS (158 assertions)
adaptive macro surface                   PASS
far -> near LOD                           1 -> 9
far -> near triangles                     120 -> 4176
detail recipe                             octaves=8, min_signal_km=4.688
manual graphical observation              PASS_BY_USER_OBSERVATION
post-cleanup git diff --check              PASS
working tree                               CLEAN
```

## Shared G5 baseline resolved

PR #43 is integrated into `feature/g5-world-feature-graph`. Accepted shared-baseline head:

```text
6e83824956f4bb9337ba0e22be6c40ccfca8bd43
```

MW10 blobs:

```text
repository  a25b7d8c358410e60e1bb7db9d3f99333a305a63
retry test  afab0c98de45c34dcf6c923d622c84835d428fa5
```

Assistant-side Linux double verification:

```text
MW10 lock release retry          PASS — 12 assertions
MW10 acquire/release stress      PASS — 501 assertions / 100 cycles
G6 production contract smoke     PASS — 115 assertions
```

The focused G6 smoke covers exact current `FluidType`, `FluidRegionId` and `WaterSurfaceQuery` production contracts with isolated generic dependencies. It supplements but does not replace the full repository regression.

## G6 resynchronization

G5 was brought into G6 through lineage-preserving composition merges:

```text
PR #47 runtime MW10 sync    -> d5879f7a5263ad98eb8ae575194e34d69a74e56c
PR #48 G5 acceptance meta   -> 854d79cbde7daf4ce72d2b89dd3d8900401fbcd0
```

Current compare is `behind G5 = 0`; current G5 is a real ancestor of G6. Hydrology semantics were not changed by the sync.

The G6 full runner was also corrected to require the final G6.4 validation state `ACCEPTED`, rather than the obsolete pre-acceptance Fix4 status.

## Remaining final gate

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

The gate now must execute past the former MW10 blocker and prove:

```text
GLOBAL/G5 lineage preflight               PASS
exact shared MW10 blobs                    PASS
G6.0-G6.4 rerun                            PASS
MW10 lock-release retry                    PASS
RUN_WORLD_REGRESSION_TESTS.ps1             PASS
final clean tree + git diff --check        PASS
```

Only after that full-tree run do we record `G6 SOURCE_ACCEPTED`. Then the next procedural checkpoint is `G7 Semantic Field Fabric`.
