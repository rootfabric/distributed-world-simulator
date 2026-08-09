# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 shared baseline              ACCEPTED / INTEGRATED
G6 Full Acceptance                     SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                ACCEPTED
G7.0 Semantic Field Contracts          ACCEPTED
G7.1 Upstream Semantic Field Adapters  IMPLEMENTED CANDIDATE
```

G7.0 full Windows acceptance on tested head `03d1dd1e61ba671456259ab660286d3376520f8e`:

```text
Godot                                  4.7.1.stable.double.custom_build.a13da4feb
G7.0 focused contracts                 PASS
M4 graphical shared gameplay Fix1      PASS — 22 assertions / 0 failures
RL3 representation streaming processes PASS — 37 assertions
main_scene_cli_all                      PASS — 6 / 6
world/core regression                   PASS
G7.0 FULL ACCEPTANCE                    PASS
working tree                            CLEAN
```

G7.1 now provides partial typed projections from accepted upstream sources:

```text
G3 provider
  geo/surface-height-m
      -> SemanticFieldSample

G5 WorldFeatureGraph
  FeatureBounds / FeatureId
      -> geo/valley-influence

G6 river/fluid geography
  WaterSurfaceResolverV1
      -> geo/river-distance-m
      -> geo/river-width-m
      -> geo/fluid-surface-distance-m
```

Registry availability:

```text
ADAPTER_AVAILABLE_G7_1
  geo/valley-influence
  geo/river-distance-m
  geo/river-width-m
  geo/fluid-surface-distance-m

VOCABULARY_ONLY_G7_0
  geo/slope
  geo/curvature
  geo/drainage-potential
  geo/continentalness
  geo/temperature-baseline
  geo/moisture-baseline
```

Ownership remains upstream:

```text
G3 provider id       PRESERVED IN PROVENANCE
G5 FeatureId         PRESERVED IN PROVENANCE
G6 FluidRegionId     PRESERVED IN PROVENANCE
new River identity   NONE
new Feature identity NONE
new Fluid identity   NONE
Geomorphology owner  NO
```

Assistant exact-engine structural evidence:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
G3 exact published blob parse/load     PASS
G5 exact published blob parse/load     PASS
G6 exact published blob parse/load     PASS
G7_1_ADAPTER_STUB_SMOKE                PASS
```

The smoke uses byte-exact adapter blobs and stubbed accepted upstream API shapes. It does not replace the full Windows repository gate.

P0 guards:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache owner
```

Current validation commands:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Candidate record:

```text
docs/checkpoints/G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_CANDIDATE_RU.md
validation/g7-1-upstream-semantic-field-adapters-validation.json
config/procedural/g7-1-upstream-semantic-field-adapters.v1.json
```

Next after acceptance:

```text
G7.2 Composition / Provenance
```
