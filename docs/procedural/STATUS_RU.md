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
G7.2 Composition / Provenance           NEXT
```

## G7.1 acceptance

Full Windows acceptance passed on tested head:

```text
61de8526448a5a2ab95745fa380cdc8b3c4ea24f
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Confirmed:

```text
G7.1 focused adapters                  PASS
G3/G5/G6 semantic adapters             PASS
RL3 representation streaming processes PASS — 37 assertions
main_scene_cli_all                      PASS — 6 / 6
world/core regression                  PASS
G7.1 adapter scope                     PASS
working tree                           CLEAN
G7.1 FULL ACCEPTANCE                   PASS
```

Fix1 closed the two real upstream-contract mismatches found by the first Windows candidate run:

```text
G3 provider result envelope: details.values
G6 WaterSurfaceSample width: channel_width_m
```

Accepted adapter blobs:

```text
G3 adapter  c728cfed5a2b3dd55d23b81b250177af19746623
G5 adapter  39ef95704cdf516b10146d2fa79b0d80bf173492
G6 adapter  437d82b7f056648045fff08f1daa57968331104c
G7.1 test   1af618356b700e5c87a55b42daa05d35b267014e
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

P0 guards remain mandatory:

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

## Next

```text
G7.2 Composition / Provenance
```

G7.2 composes partial adapter outputs into one deterministic `SemanticFieldBundle`, rejects ambiguous duplicate ownership and missing requested fields, and emits an auditable composition receipt. It must not introduce scheduler/cache, authority, persistence or new world identity ownership.
