# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g7-semantic-field-fabric
```

Current state:

```text
G6 Hydrology / Fluid Surface            SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                 ACCEPTED
G7.0 Semantic Field Contracts           ACCEPTED
G7.1 Upstream Semantic Field Adapters   ACCEPTED
G7.2 Composition / Provenance            ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  FIX1 IMPLEMENTED CANDIDATE
```

**Active GLOBAL revision:** `GLOBAL-P0-2026-08-10-R2`

R2 frontier policy:

```text
active G7 global ledger == main
historical accepted G6 may remain on its historical R1 revision
```

Verified active GLOBAL blobs:

```text
config/architecture/global-program-roadmap.v1.json
  dd18f720cd4ce6493618efe270311605aea9bbbf

docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
  3eb52a69cef73da8a784dfce7acc6a0c38185cf9
```

## Accepted semantic path

G7.0 introduced typed semantic-field identity/query/sample/provenance contracts without replacing `GeoKernel`, `GeoFieldBundle` or `GeoSample`.

G7.1 accepted projections:

```text
G3 provider
  -> geo/surface-height-m

G5 WorldFeatureGraph
  -> geo/valley-influence

G6 WaterSurfaceResolverV1
  -> geo/river-distance-m
  -> geo/river-width-m
  -> geo/fluid-surface-distance-m
```

G7.2 accepted deterministic composition:

```text
G3/G5/G6 partial adapter results
              │
              ▼
    SemanticFieldComposerV1
              │
              ├─ SemanticFieldBundle
              └─ SemanticFieldCompositionReceipt
```

Full G7.2 Windows acceptance passed on:

```text
70d9a78d8f176ce532412a64afbbcb2592623720
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Accepted G7.2 checkpoint:

```text
68c4f90dbdac0e2d9968b4461207713f5661521b
```

## G7.3 — Cross-Cell / Cross-LOD Invariance

Focused Windows evidence is already green:

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 Cross-Cell / Cross-LOD Invariance focused gate passed.
```

The proof uses LOD `2, 4, 8, 12` and the accepted G6 river fixture crossing the PX/PZ cube-sphere seam.

It verifies stable:

```text
query checksum
bundle checksum
composition receipt checksum
per-field sample checksum
per-field provenance checksum
FeatureId
FluidRegionId
```

while representation SurfaceCellKey/resolution changes.

## G7.3 Fix1 full-gate hygiene

The first full gate passed R2 preflight but `git diff --check` stopped on canonical Markdown hard-break spaces in the byte-matched main roadmap.

Fix1 does not mutate the canonical roadmap. The runner first proves:

```text
local GLOBAL roadmap blob == origin/main roadmap blob
```

then excludes only that already-verified upstream Markdown file from the local G7.3 `diff --check`. Every other G7.3/P0-sync file remains under strict whitespace hygiene.

Fix1 runner commit:

```text
73ca4a0d356eb7ed18aa813c19f617b7b2c29137
```

## Ownership / P0 guards

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
FluidTypeId != MaterialDefinitionId

G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache execution owner
G7 != Geomorphology

SemanticFieldCompositionReceipt != world identity
```

Validation now requires only the full gate rerun:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Expected final marker:

```text
G7.3 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-10-R2
Active GLOBAL-P0 main alignment: PASS
Canonical GLOBAL roadmap byte-match to main: PASS
G7.2 ACCEPTED ancestor: PASS
G7.3 invariance scope: PASS
Cross-cell / cross-LOD semantic invariance: PASS
World/core regression: PASS
Working tree: CLEAN
```

Next after G7.3 acceptance:

```text
G7.4 — Semantic Field Lab
```
