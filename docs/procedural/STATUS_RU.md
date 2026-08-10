# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Global revision:** `GLOBAL-P0-2026-08-10-R2`

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
G7.3 Cross-Cell / Cross-LOD Invariance  ACCEPTED
G7.4 Semantic Field Lab                  IMPLEMENTED CANDIDATE
```

## Active frontier

Machine-readable GLOBAL-P0 frontier moved in `main` first and is synchronized to active G7:

```text
GLOBAL-P0-2026-08-10-R2
world_generation.stage = G7.4 Semantic Field Lab
```

Current active GLOBAL config blob:

```text
61939301c5ca21c3c152ba0a76b2c5c0617cea53
```

Historical accepted G6 remains on its historical R1 revision under R2 policy.

## G7.3 acceptance

Accepted Windows evidence on tested head:

```text
910899a906e684d6793cd74ba898d68c457a37b4
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Final gate:

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 FULL ACCEPTANCE: PASS
Active GLOBAL-P0 main alignment: PASS
Canonical GLOBAL roadmap byte-match to main: PASS
G7.2 ACCEPTED ancestor: PASS
Cross-cell / cross-LOD semantic invariance: PASS
World/core regression: PASS
main_scene_cli_all: 6 PASS / 0 FAIL
Working tree: CLEAN
```

Accepted invariants:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
same world point -> same semantic bundle/provenance across LOD 2/4/8/12
query order invariant
PX/PZ seam invariant
FeatureId stable across cells
FluidRegionId stable across cells
```

Record:

```text
docs/checkpoints/G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_ACCEPTED_RU.md
validation/g7-3-cross-cell-cross-lod-invariance-validation.json
```

## G7.4 candidate

G7.4 is derived visual/debug presentation over accepted semantic samples.

It visualizes exactly five currently backed fields:

```text
1 geo/surface-height-m
2 geo/valley-influence
3 geo/river-distance-m
4 geo/river-width-m
5 geo/fluid-surface-distance-m
```

It intentionally does **not** synthesize the six vocabulary-only fields:

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

Semantic patch:

```text
lat 0..10 deg
lon 30..62 deg
16 x 32 cells
561 semantic sample points
PX/PZ coverage
```

Pipeline per point:

```text
SemanticFieldQuery
 -> G3/G5/G6 adapters
 -> SemanticFieldComposerV1
 -> SemanticFieldBundle + CompositionReceipt
 -> derived vertex/color presentation
```

Presentation-only state:

```text
field selector
colors
camera/orbit
mesh triangulation/density
HUD
river centerline overlay
```

None of it enters canonical semantic checksums.

### Automated gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Required automated marker:

```text
G7.4 AUTOMATED ACCEPTANCE: PASS
MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED
```

### Graphical lab

```powershell
.\START_G7_4_SEMANTIC_FIELD_LAB.ps1 -GodotPath $Godot
```

Controls:

```text
1..5 field modes
F river centerline
W/S zoom
A/D yaw
Q/E pitch
Space auto-orbit
R reset
```

Next after G7.4 acceptance:

```text
G7 Full Acceptance
```
