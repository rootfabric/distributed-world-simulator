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
G7.3 Cross-Cell / Cross-LOD Invariance  FIX1 IMPLEMENTED CANDIDATE
```

## P0 frontier state

Active world-generation frontier is governed by `GLOBAL-P0-2026-08-10-R2`:

```text
main                              R2 canonical ledger
feature/g7-semantic-field-fabric  R2 active frontier
feature/g6-hydrology-fluid-surface-v0  R1 historical accepted ancestor
```

R2 explicitly allows historical accepted/frozen branches to remain on their historical global revision; active G7 must match `main` byte-equivalently instead of forcing a G6 rewrite.

Current verified active GLOBAL blobs:

```text
config/architecture/global-program-roadmap.v1.json
  dd18f720cd4ce6493618efe270311605aea9bbbf

docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
  3eb52a69cef73da8a784dfce7acc6a0c38185cf9
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

## G7.3 focused evidence

Windows focused gate:

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 Cross-Cell / Cross-LOD Invariance focused gate passed.
```

Confirmed:

```text
FeatureId stable across representation cells PASS
FluidRegionId stable across cells             PASS
one river spans multiple cells                PASS
PX/PZ seam                                     PASS
semantic samples on both seam sides           PASS
PX centerline river-distance ~= 0              PASS
PZ centerline river-distance ~= 0              PASS
```

## G7.3 Fix1

The first full-gate run passed R2 preflight and stopped before runtime regression only because `git diff --check` interpreted canonical Markdown hard-break spaces in `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md` as trailing whitespace.

That roadmap is already required to be byte-identical to `origin/main`, so Fix1 does not alter it. Instead the full gate now:

```text
prove canonical GLOBAL roadmap blob == main
then exclude only that verified upstream file from local G7.3 diff --check
keep every other G7.3/P0-sync file under strict diff --check
```

Fix1 runner commit:

```text
73ca4a0d356eb7ed18aa813c19f617b7b2c29137
```

Focused semantic runtime is unchanged; only the full acceptance harness and evidence docs changed.

## G7.3 invariants

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

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Next if accepted:

```text
G7.4 Semantic Field Lab
```
