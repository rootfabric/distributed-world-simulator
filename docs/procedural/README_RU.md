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
G7.3 Cross-Cell / Cross-LOD Invariance  ACCEPTED
G7.4 Semantic Field Lab                  IMPLEMENTED CANDIDATE
```

**Active GLOBAL revision:** `GLOBAL-P0-2026-08-10-R2`

Machine-readable active frontier is synchronized with `main`:

```text
world_generation.stage = G7.4 Semantic Field Lab
config blob = 61939301c5ca21c3c152ba0a76b2c5c0617cea53
```

R2 historical policy still allows accepted G6 to remain on R1.

## Accepted semantic path

```text
G7.0 contracts
      ↓
G7.1 G3/G5/G6 adapters
      ↓
G7.2 deterministic composition + provenance receipt
      ↓
G7.3 cross-cell / cross-LOD invariance
      ↓
G7.4 derived semantic visualization
```

G7.3 Windows acceptance proved:

```text
122 focused assertions PASS
LOD 2 / 4 / 8 / 12 invariant
PX/PZ seam invariant
FeatureId stable
FluidRegionId stable
world/core regression PASS
main_scene_cli_all 6 PASS / 0 FAIL
working tree CLEAN
```

Accepted G7.3 tested head:

```text
910899a906e684d6793cd74ba898d68c457a37b4
```

## G7.4 Semantic Field Lab

G7.4 is a presentation consumer, not a new semantic owner.

It builds a deterministic 561-point surface patch around the accepted G6 river fixture and runs the real G7 pipeline per point:

```text
SemanticFieldQuery
 -> G3 surface adapter
 -> G5 feature adapter
 -> G6 fluid adapter
 -> SemanticFieldComposerV1
 -> SemanticFieldBundle / CompositionReceipt
 -> visual mesh
```

Available visual modes:

```text
1 geo/surface-height-m
2 geo/valley-influence
3 geo/river-distance-m
4 geo/river-width-m
5 geo/fluid-surface-distance-m
```

The following vocabulary-only fields are explicitly shown as unavailable rather than filled with fake formulas:

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

This distinction is intentional: G7.4 visual evidence may reveal existing semantics, but it must not quietly invent future G8/environment semantics.

### Presentation boundary

```text
colors != semantic values
camera != semantic query
mesh density != canonical identity
field selection != canonical mutation
river line overlay != FluidRegion truth
HUD != provenance
```

The geometry always uses accepted `geo/surface-height-m`; switching 1..5 changes only derived coloring.

### Run automated acceptance

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Expected end:

```text
G7.4 AUTOMATED ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-10-R2
G7.3 ACCEPTED ancestor: PASS
G7.4 visual-lab scope: PASS
Five adapter-backed semantic fields: PASS
Six vocabulary-only fields not faked: PASS
World/core regression: PASS
Working tree: CLEAN
MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED
```

### Run graphical lab

```powershell
.\START_G7_4_SEMANTIC_FIELD_LAB.ps1 -GodotPath $Godot
```

Controls:

```text
1..5  semantic fields
F     river centerline
W/S   zoom
A/D   yaw
Q/E   pitch
Space auto orbit
R     reset
```

The HUD exposes current field id, unit, registry availability, min/max range, sample count, faces, center bundle/provenance checksum prefixes and the list of vocabulary-only fields that are not rendered.

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

G7.4 != renderer foundation
G7.4 colors/camera/mesh != canonical truth
SemanticFieldCompositionReceipt != world identity
```

Current G7.4 delta from accepted G7.3 checkpoint is restricted to 18 visual-lab/frontier/docs/test files. It changes no G3/G5/G6 adapter, composer, Hydrology, Matter or Network runtime.

Next after graphical G7.4 acceptance:

```text
G7 Full Acceptance
```

Then the world-generation frontier can move to G8 Geomorphology, where river/valley semantics finally begin to modify canonical terrain shape.
