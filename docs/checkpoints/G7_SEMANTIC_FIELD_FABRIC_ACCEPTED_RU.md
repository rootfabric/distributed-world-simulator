# G7 Semantic Field Fabric — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**Tested head:** `a75a60b6da739cc759e1fb40510a98942bce4cde`

## Decision

G7 Semantic Field Fabric is **ACCEPTED**.

Accepted sub-stages:

```text
G7.0 Semantic Field Contracts                 ACCEPTED
G7.1 Upstream Semantic Field Adapters         ACCEPTED
G7.2 Composition / Provenance                 ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance        ACCEPTED
G7.4 Semantic Field Lab                       ACCEPTED
G7 Full Acceptance                            PASS
```

The final Windows aggregate gate passed with the exact Godot `4.7.1.stable.double.custom_build.a13da4feb` build. World/core regression passed through NX4, RL3 representation streaming reported 37 assertions PASS, `main_scene_cli_all` reported 6 PASS / 0 FAIL, lifecycle reached STOPPED, and the final working tree was clean.

## Accepted semantic boundary

G7 provides stable semantic-field contracts, accepted adapters over G3/G5/G6 truth, deterministic composition/provenance, cross-cell/cross-LOD invariance, and a derived graphical lab proving that presentation changes do not redefine semantic truth.

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
camera / color / mesh density / debug shell != canonical truth
```

G7 does not own WorldAddress, universal WorldQuery, authority routing, interest management, persistence durability, network replication, material ontology, or scheduler/cache foundations.

## Non-blocking presentation debt

The current four presentation LODs switch visibly. This is not a G7 acceptance blocker. A future rendering/streaming stage may add more levels, hysteresis, neighbor stitching, or geomorphing while continuing to reuse the same semantic truth.

## Next

The World Generation frontier may advance to **G8 — Geomorphology**.

G8 is allowed to derive procedural valley incision, river-channel incision, bank/floodplain shaping, and erosion/deposition baseline from accepted G7/G6/G5/G3 truth. It must not take ownership of player excavation, persistent Matter mutations, global world addressing, authority, persistence, or material ontology.
