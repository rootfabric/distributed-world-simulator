# Procedural Planetary Generation Lab

Current branch:

```text
feature/g3-casual-macro-surface
```

Current state:

```text
G2 ACCEPTED
G3 IMPLEMENTED CANDIDATE
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G3_CASUAL_MACRO_SURFACE_CANDIDATE_RU.md`
3. `docs/checkpoints/G2_PLANETARY_CELLS_LOD_ACCEPTED_RU.md`
4. `docs/plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`
5. `docs/plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`
6. `docs/architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`
7. `docs/validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`

## Current stack

```text
PlanetDefinition / Geo contracts       G0
              ↓
body-fixed geodesy / sphere shape      G1
              ↓
cube-sphere cells + adaptive LOD        G2
              ↓
continuous global macro height field   G3
```

G3 is the first non-flat planet surface. `CasualMacroTerrainProviderV1` samples deterministic low-frequency 3D noise using normalized body-fixed direction and returns `geo/surface-height-m`.

The provider never receives cell/face/LOD identity. Therefore a mountain is a world field, not something generated independently inside each streaming cell.

Visual lab:

```text
res://scenes/labs/procedural/g3_casual_macro_surface_lab.tscn
```

Focused tests:

```powershell
.\RUN_G3_MACRO_SURFACE_TESTS.ps1
```

Full gate:

```powershell
.\RUN_G3_FULL_ACCEPTANCE.ps1
```

After G3 acceptance, G4 proves provider composition and replacement without changing renderer, SurfaceCellKey, GeoKernel call sites or streaming semantics.
