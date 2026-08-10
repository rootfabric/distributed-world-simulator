# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                    ACCEPTED
G6.1 CasualRiverProviderV1              ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity  ACCEPTED
G6.3 Runtime WaterSurfaceQuery          ACCEPTED
G6.4 Casual Visual River Lab            ACCEPTED
G5 + MW10 shared baseline               ACCEPTED / INTEGRATED
G6 Full Acceptance                      SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                 ACCEPTED
G7.0 Semantic Field Contracts           ACCEPTED
G7.1 Upstream Semantic Field Adapters   ACCEPTED
G7.2 Composition / Provenance            ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  IMPLEMENTED CANDIDATE
```

## G7.2 acceptance

Full Windows acceptance passed on tested head:

```text
70d9a78d8f176ce532412a64afbbcb2592623720
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Confirmed:

```text
G7.2 composition scope                 PASS
Deterministic bundle + provenance      PASS
world/core regression                  PASS
main_scene_cli_all                      PASS — 6 / 6
working tree                            CLEAN
G7.2 FULL ACCEPTANCE                    PASS
```

Accepted G7.2 checkpoint:

```text
68c4f90dbdac0e2d9968b4461207713f5661521b
```

## G7.3 candidate

G7.3 is proof-only: accepted G7 semantic runtime is not modified.

It proves:

```text
same world point
+ same canonical SemanticFieldQuery
+ different SurfaceCellKey / LOD representation path
= same semantic bundle / provenance
```

LOD proof levels:

```text
2, 4, 8, 12
```

Required invariants:

```text
SemanticFieldQuery has no SurfaceCellKey or LOD
same query checksum across representation paths
same bundle checksum across LOD
same receipt checksum across LOD
same sample/provenance checksums across LOD
query field order does not affect result
one river spans multiple cells
PX/PZ seam preserves river semantic behavior
G5 FeatureId remains stable across cells
G6 FluidRegionId remains stable across cells
```

Representation resolution changes with LOD, but representation density is not canonical semantic identity.

P0 boundaries remain:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
G7.3 != scheduler/cache
G7.3 != authority/interest
G7.3 != persistence/network
```

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Next if accepted:

```text
G7.4 Semantic Field Lab
```
