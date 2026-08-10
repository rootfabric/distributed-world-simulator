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
G7.1 Upstream Semantic Field Adapters  ACCEPTED
G7.2 Composition / Provenance           ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  NEXT
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

Accepted composition policy:

```text
semantic-composition-policy/require-complete-v1

missing requested field       REJECT
duplicate field ownership     REJECT
duplicate adapter             REJECT
unrequested contributed field REJECT
input ordering                 NORMALIZED BY ADAPTER_ID
```

The accepted composer preserves adapter-produced samples and their upstream provenance checksums; the receipt pins query, bundle, sample and provenance checksums without becoming world identity.

P0 boundaries remain:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
composer != scheduler/cache
composer != authority/interest
composer != persistence/network
composer != material ontology
composer != geomorphology
receipt != world identity
```

## Next

```text
G7.3 Cross-Cell / Cross-LOD Invariance
```

G7.3 must prove that representation addressing and LOD change sampling density/cell membership only, not canonical semantic values, sample/provenance checksums, FeatureId/FluidRegionId or composition results.
