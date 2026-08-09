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
G7.1 Upstream Semantic Field Adapters  FIX1 IMPLEMENTED CANDIDATE
```

G7.0 full Windows acceptance on tested head `03d1dd1e61ba671456259ab660286d3376520f8e` remains valid.

## G7.1 current state

The first real full-checkout G7.1 run correctly failed inside the focused adapter gate:

```text
G7.1 focused assertions reached        54
G7.1 focused failures                  6
world/core regression after G7.1       NOT RUN
full acceptance                        FAIL FAST
```

The six failures are explained by two real upstream-contract mismatches in the initial candidate.

### Fix1 — G3 provider result envelope

Accepted `GeoProvider.success(values)` returns:

```text
details
  values
    geo/surface-height-m
```

The initial adapter incorrectly treated `details` itself as the value map. That caused the G3 adapter to fail and then produced five G3 assertions before an empty `source_refs` lookup aborted the remaining G3 assertions.

Fix1 now consumes exactly:

```text
provider_result.details.values
```

and the acceptance test explicitly guards the canonical envelope.

### Fix1 — G6 channel width key

Accepted `WaterSurfaceSample` uses:

```text
channel_width_m
```

not:

```text
width_m
```

Both adapter projection and direct-comparison test now use `channel_width_m` and explicitly reject the stale alias.

Current Fix1 blobs:

```text
G3 adapter     c728cfed5a2b3dd55d23b81b250177af19746623
G5 adapter     39ef95704cdf516b10146d2fa79b0d80bf173492
G6 adapter     437d82b7f056648045fff08f1daa57968331104c
G7.1 test      1af618356b700e5c87a55b42daa05d35b267014e
```

The previous assistant stub smoke is explicitly superseded: its stubs were too permissive and did not reproduce the exact accepted G3/G6 result shapes. It is not acceptance evidence.

If all real paths complete, the strengthened focused test should now end with:

```text
G7.1 Upstream Semantic Field Adapters: 59 assertions, 0 failures
```

Ownership remains unchanged:

```text
G3 provider id       PRESERVED IN PROVENANCE
G5 FeatureId         PRESERVED IN PROVENANCE
G6 FluidRegionId     PRESERVED IN PROVENANCE
new River identity   NONE
new Feature identity NONE
new Fluid identity   NONE
Geomorphology owner  NO
```

P0 guards remain:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache owner
G7.1 != Geomorphology
```

Rerun:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

G7.1 remains unaccepted until the full Windows gate passes. Next after acceptance remains:

```text
G7.2 Composition / Provenance
```
