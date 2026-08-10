# G7.4 Semantic Field Lab — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Project Control:** `PC0-2026-08-10-R1`  
**Branch:** `feature/g7-semantic-field-fabric`  
**Parent:** `G7.3 Cross-Cell / Cross-LOD Invariance — ACCEPTED`

## Decision

`G7.4 Semantic Field Lab` is **ACCEPTED**.

The stage proved that one stable semantic source can drive different derived presentation LODs without making camera distance, mesh density, rendering or debug presentation part of canonical world truth.

## Automated evidence

Exact Windows engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Focused Fix4 evidence:

```text
G7.4 contracts                    80 assertions / 0 failures
headless semantic lab smoke       PASS
semantic samples                  561
adapter-backed fields             5
vocabulary-only fields            6
faces                             PX,PZ
```

Full G7.4 acceptance tested head:

```text
ddacaf18a5c4b57c708562538a71065240d73ddb
```

Full gate:

```text
PC0 operational G frontier           PASS
PC0 G health is not RED              PASS
G7.3 ACCEPTED ancestor               PASS
G7.4 visual-lab scope                PASS
world/core regression                PASS
main_scene_cli_all                    6 PASS / 0 FAIL
NX4 client prediction/reconciliation PASS
lifecycle final state                STOPPED
working tree                         CLEAN
G7.4 AUTOMATED ACCEPTANCE            PASS
```

## Manual graphical evidence

User observation on 2026-08-10 confirms:

```text
LOD0..LOD3 visibly switch                         PASS
33x17 -> 17x9 -> 9x5 -> 5x3 presentation grids PASS
semantic source stays at 561                     PASS
false black sphere-occlusion holes absent        PASS
cyan diagnostic river ribbon visible             PASS
F toggles river ribbon                           PASS
fields 1..5 recolor only at fixed LOD            PASS
no obvious PX/PZ semantic seam                   PASS
```

## Fix4 closure

Fix4 is presentation-only:

- the semantic patch receives a derived radial shell lift so negative/coarse geometry is not hidden by the debug sphere;
- the canonical river centerline is shown as a thin diagnostic triangle-strip ribbon;
- neither change alters semantic samples, semantic queries, `FeatureId`, `FluidRegionId` or canonical checksums.

## Non-blocking presentation debt

LOD switching is visibly abrupt. This does **not** block G7.4 acceptance because the accepted contract is semantic/presentation separation, not final renderer quality.

Future presentation work may add more LOD levels, hysteresis, neighbor stitching and/or geomorphing. Those improvements must remain derived presentation and must not change canonical semantic identity.

## Accepted boundary

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
camera / mesh density / color != canonical truth
```

G7 still does not own WorldAddress, universal WorldQuery, authority routing, interest management, persistence durability, network replication, material ontology or scheduler/cache foundations.

## Next stage

`G7 Full Acceptance`.

Only after G7 Full Acceptance is green may the World Generation frontier proceed to `G8 — Geomorphology`.
