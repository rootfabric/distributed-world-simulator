# G8.1 Valley Incision Baseline — IMPLEMENTED CANDIDATE

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`
**Parent:** `G8.0 Geomorphology Contracts — ACCEPTED`

## Purpose

G8.1 is the first stage that turns accepted semantic world information into actual procedural surface shaping.

Input semantics:

```text
geo/surface-height-m
geo/valley-influence
```

The accepted G5/G7 `geo/valley-influence` remains a semantic influence derived from canonical valley feature bounds. G8.1 does not redefine the feature. It only maps the influence to a replaceable procedural incision formula.

## Baseline formula

```text
incision_depth_m = valley_max_depth_m * pow(valley_influence, valley_exponent)
valley_delta_m   = -incision_depth_m
```

Properties:

- influence `0` -> no incision;
- influence `1` -> profile maximum valley depth;
- monotonic between those limits;
- valley delta can never raise the surface;
- magnitude is bounded by `valley_max_depth_m`;
- river-channel, bank, floodplain and erosion/deposition components remain exactly zero at G8.1;
- same semantic bundle + same profile -> same deformation checksum.

The output is the accepted G8.0 deformation contract and binds both source semantic bundle checksum and profile checksum.

## Ownership boundary

G8.1 has no `SurfaceCellKey`, LOD, camera, representation, authority, interest, Matter mutation, persistent terrain damage, material definition or network ownership dependency.

## Focused validation

```powershell
cd C:\Godot\lunar-world-g6-fluid

git fetch origin --prune
git switch -C feature/g8-geomorphology origin/feature/g8-geomorphology

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G8_1_VALLEY_INCISION_TESTS.ps1 `
    -GodotPath $Godot
```

A green focused run is required before the fresh full world/core regression and before G8.2 River Channel Incision begins.
