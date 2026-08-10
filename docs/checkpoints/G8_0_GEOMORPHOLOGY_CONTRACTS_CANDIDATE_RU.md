# G8.0 Geomorphology Contracts — IMPLEMENTED CANDIDATE

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`
**Parent:** `G7 Semantic Field Fabric — ACCEPTED`

## Purpose

G8 starts with contracts, not terrain formulas. The first checkpoint defines exactly what a procedural geomorphology layer may produce while preserving the accepted G7 semantic and ownership boundaries.

A geomorphology result is a deterministic signed height deformation over an input surface sample:

```text
resolved_surface_height_m
    = source_surface_height_m
    + valley_delta_m
    + river_channel_delta_m
    + bank_delta_m
    + floodplain_delta_m
    + erosion_deposition_delta_m
```

Valley and river-channel deltas are non-positive. Bank, floodplain and erosion/deposition deltas are signed because those processes may either lower or raise the procedural baseline.

## Contracts

```text
scripts/simulation/procedural/geomorphology/geomorphology_profile.gd
scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd
```

The deformation sample binds:

```text
body_id
frame_id
body_fixed_position_m
profile_id + version + checksum
source_semantic_bundle_checksum
source_surface_height_m
five component deltas
sum / resolved surface
checksum
```

It intentionally does not contain `SurfaceCellKey`, LOD, authority/interest regions, Matter revision, MaterialDefinitionId, network peer identity or persistence identity.

## Planned semantic inputs for G8.1+

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
```

G8.0 does not yet claim that those inputs imply a specific terrain formula. It only freezes the output boundary so formulas can be replaced without changing world identity.

## G8 roadmap

```text
G8.0 Contracts
G8.1 Valley Incision Baseline
G8.2 River Channel Incision
G8.3 Banks and Floodplain Shaping
G8.4 Erosion / Deposition Baseline
G8.5 Cross-Cell / Cross-LOD Invariance
G8.6 Geomorphology Visual Lab
G8 Full Acceptance
```

## Ownership boundary

G8 owns procedural geomorphology baseline shaping only. It does not own player excavation, persistent terrain damage, Matter transactions/storage, material ontology, global world addressing, authority routing, persistence durability, network replication or universal WorldQuery.

## Focused gate

```powershell
cd C:\Godot\lunar-world-g6-fluid
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G8_0_GEOMORPHOLOGY_CONTRACTS_TESTS.ps1 -GodotPath $Godot
```

G8.1 must not begin until this focused contract gate is green and the resulting exact tested head is recorded.
