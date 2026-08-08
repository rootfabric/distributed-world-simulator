# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation branch:** `feature/g2-planetary-cells-lod`
**Purpose:** единая точка фиксации прогресса программы.

---

## Текущее состояние

```text
PROGRAM: Procedural Planetary Generation Fabric
G0: ACCEPTED
G1: IMPLEMENTED CANDIDATE — full-checkout gate still pending
G2: IMPLEMENTED CANDIDATE
G2 EXACT-ENGINE FOCUSED: PASS
PRODUCTION RUNTIME CHANGED: NO
PRODUCTION TERRAIN CHANGED: NO
CURRENT GATE: G2 full-checkout acceptance including G1 dependency checks
NEXT AFTER G2 ACCEPTED: G3 — Mega Casual Macro Surface
```

G2 is intentionally stacked on the current G1 candidate at the user's request. This does not retroactively mark G1 accepted; the full G2 wrapper includes the G1 focused dependency suite plus the complete world/core regression.

---

## G0 — accepted foundation

```text
branch:         feature/g0-geo-contracts
accepted head: 7632ed576a3c0d9007c0ff1296d1d89cd43756d7
decision:       ACCEPTED
```

G0 froze canonical Geo contracts, deterministic provider composition and renderer-independent `GeoKernel` semantics.

---

## G1 — dependency status

```text
stage:       G1 — Geodesy + Body Shape
branch:      feature/g1-geodesy-body-shape
base:        feature/g0-geo-contracts
head:        b30b1cad64a7176f2e3155fbe5cea2ec811c2e7a
decision:    IMPLEMENTED CANDIDATE
```

Implemented:

```text
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
BodyShapeProvider
SphereBodyShapeProvider
GeodesyService
```

Exact-engine isolated evidence already recorded:

```text
G1 deep geodesy smoke:          PASS — 76 assertions
G1 fly-in geodesy continuity:   PASS — 117 assertions
```

G1 full checkout regression was still pending when G2 implementation started.

---

## G2 — implementation record

```text
stage:                  G2 — Planetary Surface Cells + LOD
branch:                 feature/g2-planetary-cells-lod
base branch:            feature/g1-geodesy-body-shape
base commit:            b30b1cad64a7176f2e3155fbe5cea2ec811c2e7a
decision:               IMPLEMENTED CANDIDATE
production worlds:      unchanged
production terrain:     unchanged
GeoKernel semantics:    unchanged
renderer dependency:    none in G2 core
network dependency:     none
```

Implemented core:

```text
SurfaceCellKey
SurfaceLodPolicy
CubeSphereAddressing
SurfaceLodSelector
SurfaceCellLifecycle
```

Address shape:

```text
{ body_id, face, lod, x, y }
faces = PX NX PY NY PZ NZ
```

Core operations:

```text
direction/body-position → cell
face UV ↔ body direction
cell UV bounds / center / corners
quadtree parent / children
same-level cross-face neighbors
LOD refinement + hysteresis
bounded deterministic leaf selection
REQUESTED → BUILDING → ACTIVE → RETIRING lifecycle
```

---

## G2 architecture invariants

```text
LOD != World State
SurfaceCellKey != terrain content
cell boundary != feature boundary
selection is observer-dependent presentation policy
GeoSample remains observer/LOD independent
core has no Node/Mesh/Camera/RenderingServer dependency
```

Same semantic point can be addressed at many LODs; the underlying G0 GeoSample remains identical.

---

## G2 exact-engine evidence

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Focused:

```text
cold editor import:                    PASS
G2 core/addressing/LOD:                PASS — 16,190 assertions
G2 fly-in/out continuity:              PASS — 2,412 assertions
debug lab headless launch:             PASS
focused Linux wrapper:                 PASS (~16 s in isolated harness)
```

Seam validation:

```text
all cells exhaustive through LOD3
all six cube-face boundaries sampled at LOD4 / LOD8 / LOD12
neighbor same-level identity PASS
cross-face reciprocal adjacency PASS
shared edge-corner agreement PASS
```

Fly-in/out validation:

```text
50,000 km → surface → 50,000 km
leaf budget bounded
leaf cover has no ancestor overlap
hysteresis stable
safe incoming-active-before-retiring-release handoff
retired records reclaimed
```

A performance issue discovered during validation was fixed before handoff: previous-split hysteresis lookup no longer scans every previous leaf per candidate; it uses a precomputed ancestor identity index and fast validated cell identity tokens.

---

## G2 debug lab

```text
res://scenes/labs/procedural/g2_planetary_cells_lab.tscn
```

Controls:

```text
W/S altitude
A/D longitude
Q/E latitude
```

The lab visualizes the selected cube-sphere cell grid with LOD colors and HUD counters. Renderer code is isolated from the core.

---

## G2 acceptance gate

Focused runners:

```text
RUN_G2_PLANETARY_CELLS_TESTS.ps1
RUN_G2_PLANETARY_CELLS_TESTS.sh
```

Full checkout:

```powershell
.\RUN_G2_FULL_ACCEPTANCE.ps1
```

Required final evidence:

```text
G1 focused dependency suite:          PASS
G2 focused suite:                     PASS
full world/core regression:           PASS
Breakpoint runtime :9081 collisions:  0
git diff --check vs G1:               PASS
```

Until that real-checkout wrapper is green, G2 remains `IMPLEMENTED CANDIDATE`.

---

## Канонический порядок программы

```text
G0  Contracts freeze v0                     ACCEPTED
G1  Geodesy + Body Shape                     IMPLEMENTED CANDIDATE
G2  Planetary Surface Cells + LOD            IMPLEMENTED CANDIDATE
G3  Mega Casual Macro Surface                NEXT AFTER G2 ACCEPTED
G4  Provider Composition / Replacement       BLOCKED BY G3
G5  WorldFeature + FeatureGraph              BLOCKED BY G4
G6  Mega Casual River                        BLOCKED BY G5
G7  Semantic Geo Fields                      BLOCKED BY G6
G8  Casual Geomorphology                     BLOCKED BY G7
G9  Geology Lite                             BLOCKED BY G8
G10 GeoVolume Contract                       BLOCKED BY G9
G11 Mega Casual Cave                         BLOCKED BY G10
G12 Cache + Generation Scheduler             BLOCKED BY G11
G13 Progressive Detail Contract Freeze       BLOCKED BY G12
G14 Simple Detail Generator                  BLOCKED BY G13
G15 Multiple PlanetRecipe Acceptance         BLOCKED BY G14
G16 Generator Substitution Acceptance        BLOCKED BY G15
```

After `G13 ACCEPTED` the parallel GH0→GH6 high-resolution track opens. Future integration remains G17 Matter Bridge, G18 Representation LOD Integration, G19 Network Manifest Integration.

---

## Следующее действие

On the full Windows checkout of `feature/g2-planetary-cells-lod`:

```powershell
.\RUN_G2_FULL_ACCEPTANCE.ps1
```

After PASS record G1/G2 dependency evidence precisely, mark G2 accepted, then open:

```text
feature/g3-casual-macro-surface
```

G3 must use the G2 cells only as sampling/representation scopes. Terrain geography itself must remain continuous and independent from cell boundaries.

---

## Документы

```text
docs/procedural/README_RU.md
docs/procedural/STATUS_RU.md
docs/checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md
docs/checkpoints/G1_FLY_IN_CONTINUITY_EVIDENCE_RU.md
docs/checkpoints/G2_PLANETARY_CELLS_LOD_CANDIDATE_RU.md
```
