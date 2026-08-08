# Procedural Planetary Generation Lab — индекс программы

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation:** `feature/g2-planetary-cells-lod`
**Current state:** `G2 IMPLEMENTED CANDIDATE`

---

## С чего начинать после перерыва

1. [`STATUS_RU.md`](STATUS_RU.md) — canonical current state and next gate.
2. [`../checkpoints/G2_PLANETARY_CELLS_LOD_CANDIDATE_RU.md`](../checkpoints/G2_PLANETARY_CELLS_LOD_CANDIDATE_RU.md) — current G2 implementation/evidence.
3. [`../checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md`](../checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md) — G1 dependency checkpoint.
4. [`../checkpoints/G1_FLY_IN_CONTINUITY_EVIDENCE_RU.md`](../checkpoints/G1_FLY_IN_CONTINUITY_EVIDENCE_RU.md) — G1 fly-in exact-engine evidence.
5. [`../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md) — implementation order G0–G19.
6. [`../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`](../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md) — architectural doctrine.
7. [`../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`](../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md) — cross-stage acceptance invariants.

---

## Где мы сейчас

```text
G0 Contracts Freeze v0
        ACCEPTED
          │
          ▼
G1 Geodesy + Body Shape
   IMPLEMENTED CANDIDATE
          │
          ▼
G2 Planetary Cells + LOD
   IMPLEMENTED CANDIDATE
          │
          │ full-checkout gate
          ▼
G3 Mega Casual Surface
          │
          ▼
G4 Provider Replacement Review
          │
          ▼
G5 FeatureGraph
          │
          ▼
G6 Long River
          │
          ▼
G7 Semantic Fields
          │
          ▼
G8 Geomorphology
          │
          ▼
G9 Geology Lite
          │
          ▼
G10 GeoVolume
          │
          ▼
G11 Cave Fly-In
          │
          ▼
G12 Cache/Scheduler
          │
          ▼
G13 DetailPatch Contract
          ├───────────────┐
          ▼               ▼
G14→G16 MAIN GEO       GH0→GH6 HIGH RES
```

G2 was intentionally implemented on top of the current G1 candidate at the user's request. Acceptance remains gated by the real full checkout regression.

---

## Что теперь существует

### G0

```text
PlanetDefinition / PlanetRecipe
GeoProvider graph
GeoKernel
Surface / Volume query boundary
deterministic semantic samples
```

### G1

```text
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
BodyShapeProvider
SphereBodyShapeProvider
GeodesyService
```

### G2

```text
SurfaceCellKey
SurfaceLodPolicy
CubeSphereAddressing
SurfaceLodSelector
SurfaceCellLifecycle
```

Planetary addressing:

```text
body_id + face + lod + x + y
faces: PX NX PY NY PZ NZ
quadtree: parent + 4 children
cross-face same-level neighbors
```

LOD:

```text
observer-dependent selection
refine/coarsen hysteresis
max leaf budget
deterministic selection hash
previous-split ancestor index
```

Lifecycle:

```text
REQUESTED → BUILDING → ACTIVE → RETIRING → removed
```

---

## Главный G2 инвариант

```text
LOD chooses HOW MUCH of the same world to represent.
LOD never chooses WHICH world exists.
```

The same body-fixed point sampled through `GeoKernel` returns the same semantic `GeoSample` regardless of whether G2 addresses it at LOD0, LOD2, LOD5, LOD9 or LOD14.

Cells are therefore spatial/representation addresses, not terrain ownership boundaries and not procedural feature identities.

---

## Debug lab

Run:

```text
res://scenes/labs/procedural/g2_planetary_cells_lab.tscn
```

Controls:

```text
W/S — altitude
A/D — longitude
Q/E — latitude
```

It shows an adaptive colored cube-sphere cell grid, altitude, leaf count, max LOD and selection hash.

Renderer code exists only in the lab layer. Core G2 remains independent from Mesh, Camera3D, SceneTree and RenderingServer.

---

## Exact-engine evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold import:                         PASS
G2 core/addressing/LOD:             PASS — 16,190 assertions
G2 fly-in/out continuity:           PASS — 2,412 assertions
G2 debug lab headless launch:       PASS
focused Linux runner:               PASS (~16 s isolated)
```

The validation found and fixed a hot-path issue before handoff: previous hysteresis descendants are now indexed instead of linearly scanned for every candidate cell.

---

## Full acceptance

On the real checkout:

```powershell
.\RUN_G2_FULL_ACCEPTANCE.ps1
```

It runs G1 dependency focused tests, G2 focused tests, full world/core regression, Breakpoint `:9081` noise audit and `git diff --check` against G1.

After PASS, G3 can start:

```text
feature/g3-casual-macro-surface
```

G3 will finally put a simple continuous macro terrain field onto this addressing/LOD foundation.
