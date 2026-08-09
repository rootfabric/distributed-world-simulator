# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED
G6.4 ACCEPTED
G6 FULL ACCEPTANCE — SOURCE_ACCEPTED
```

Architecture status remains intentionally separated:

```text
SOURCE_ACCEPTED        YES
MAIN_INTEGRATED        NO
COMPOSITION_VERIFIED   NO
PRODUCTION_READY       NO
```

Accepted G6 evidence:

```text
G6.4 contracts                         PASS — 158 assertions
Adaptive Macro Surface                 PASS
far_lod -> near_lod                    1 -> 9
far_triangles                          120 -> 4176
MW10 lock release retry                PASS — 12 assertions
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS — 6 / 0 fail
PowerShell Fix3 parser                  PASS
git diff --check G5...G6               PASS
working tree                            CLEAN
```

G6 remains P0-aligned: G5 owns river feature identity; G6 owns fluid geography/query semantics; G6.4 is derived presentation. Cell/LOD/renderer/network/authority do not own fluid identity.

Additional P0 bridge fixed after acceptance audit:

```text
FluidRegionId        = geographic fluid identity
FluidTypeId          = fluid-domain semantic class
MaterialDefinitionId = future shared P0 material identity

FluidTypeId != MaterialDefinitionId
```

Next development line:

```text
G7 Semantic Field Fabric
    -> G8 Geomorphology
    -> G9 Layered Geology
    -> G10 GeoVolume / SDF
    -> G11 Heterogeneous Body Lab
    -> G12 Scheduler / Cache / Provenance
    -> G13 Detail Contract Freeze
```

Important gates:

- G7 is a domain semantic-field fabric, not a replacement for WorldAddress / universal WorldQuery / authority / persistence / network foundations;
- G8 owns procedural river/valley incision, banks, floodplain and erosion baseline;
- G9 formal material acceptance requires the P0 Unified Material Ontology bridge;
- G10 GeoVolume/SDF must not become a second Matter implementation;
- G12 may schedule/cache/provide provenance but must not own authority or persistence;
- representation/detail experiments may run in parallel but remain derived.

Detailed plan:

```text
docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md
config/procedural/g7-g13-p0-aligned-roadmap.v1.json
```

Immediate next implementation checkpoint:

```text
G7.0 Semantic Field Contracts + Registry Vocabulary
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
