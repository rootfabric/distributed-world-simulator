# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`  
**Current implementation branch:** `feature/g3-casual-macro-surface`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                dependency baseline
G2 Planetary Surface Cells + LOD       ACCEPTED — full gate reported PASS by user
G3 Mega Casual Macro Surface           IMPLEMENTED CANDIDATE
G4 Provider Composition / Replacement  NEXT AFTER G3 ACCEPTED
```

G3 base:

```text
feature/g2-planetary-cells-lod
6319e1e312c7c663d5d05c0806f5a42cf68ad441
```

Production worlds, production terrain, Matter and network runtime remain unchanged by G3.

## G3 implementation

```text
CasualMacroTerrainProviderV1
  domain: body-fixed-unit-direction-v1
  seed: 2026080801
  nominal radius: 6,000 km
  amplitude: 900 m
  base wavelength: 600 km
  octaves: 4
  field: geo/surface-height-m
```

The provider samples one continuous deterministic 3D macro field. It does not know cube faces, cells or LOD.

## Exact-engine evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import                 PASS
G3 macro acceptance                PASS — 14,275 assertions
G3 fly-in/out macro continuity     PASS — 99 assertions
G3 visual lab headless launch      PASS
```

Critical evidence:

```text
same seed → same terrain
seed/config participate in provenance
cross-face shared points agree
coarse/fine shared points agree
same point across LOD0..14 → same macro height
50,000 km fly-in/out → same regional macro profile hash
LOD changes representation only
```

Visual lab:

```text
res://scenes/labs/procedural/g3_casual_macro_surface_lab.tscn
```

## Full gate

```powershell
.\RUN_G3_FULL_ACCEPTANCE.ps1
```

Required before acceptance:

```text
G2 focused dependency PASS
G3 focused PASS
world/core regression PASS
git diff --check vs G2 PASS
```

## Canonical roadmap

```text
G0  Contracts freeze v0                     ACCEPTED
G1  Geodesy + Body Shape                    BASELINE
G2  Planetary Surface Cells + LOD           ACCEPTED
G3  Mega Casual Macro Surface               IMPLEMENTED CANDIDATE
G4  Provider Composition / Replacement      BLOCKED BY G3 ACCEPTANCE
G5  WorldFeature / FeatureGraph             BLOCKED BY G4
G6  Mega Casual River                       BLOCKED BY G5
G7  Semantic Geo Fields                     BLOCKED BY G6
G8  Casual Geomorphology                    BLOCKED BY G7
G9  Geology Lite                            BLOCKED BY G8
G10 GeoVolume                               BLOCKED BY G9
G11 Mega Casual Cave                        BLOCKED BY G10
G12 Cache + Scheduler                       BLOCKED BY G11
G13 Progressive Detail Contract             BLOCKED BY G12
G14 Simple Detail Generator                 BLOCKED BY G13
G15 Multiple PlanetRecipe Acceptance        BLOCKED BY G14
G16 Generator Substitution Acceptance       BLOCKED BY G15
```

## Invariants

```text
Generator != Renderer
LOD != World State
Feature != Chunk
macro field != cell-local noise
GeoKernel != planet-specific monolith
procedural baseline + persistent delta = authoritative world
```
