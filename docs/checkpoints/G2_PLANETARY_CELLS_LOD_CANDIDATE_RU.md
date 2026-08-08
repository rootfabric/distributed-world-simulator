# G2 — Planetary Surface Cells + LOD — implementation candidate

**Дата:** 2026-08-08
**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Base:** `feature/g1-geodesy-body-shape @ b30b1cad64a7176f2e3155fbe5cea2ec811c2e7a`
**Implementation branch:** `feature/g2-planetary-cells-lod`
**Decision:** `IMPLEMENTED CANDIDATE`
**Production worlds changed:** NO
**Production terrain changed:** NO

---

## 1. Scope

G2 добавляет planetary addressing и representation-level LOD поверх G1 geodesy, не меняя canonical world semantics.

Core:

```text
SurfaceCellKey
SurfaceLodPolicy
CubeSphereAddressing
SurfaceLodSelector
SurfaceCellLifecycle
```

Debug lab:

```text
res://scenes/labs/procedural/g2_planetary_cells_lab.tscn
```

---

## 2. Canonical SurfaceCellKey

Address:

```text
body_id
face ∈ {PX, NX, PY, NY, PZ, NZ}
lod
x
y
```

At LOD `L` each cube face contains:

```text
2^L × 2^L cells
```

`SurfaceCellKey` is JSON-safe, checksummed and independent from renderer, camera, network transport and mesh state.

Maximum address LOD in v1:

```text
30
```

This is an address-space ceiling, not a promise to render LOD30.

---

## 3. Cube-sphere convention

Face centers:

```text
PX → +X
NX → -X
PY → +Y
NY → -Y
PZ → +Z
NZ → -Z
```

The mapping is deterministic and uses a canonical dominant-axis tie rule. Exact face edges/corners therefore have one deterministic direction→face identity, while neighboring faces still share the same geometric edge directions.

Implemented operations:

```text
root_cells()
body_position_to_cell()
direction_to_cell()
direction_to_face_uv()
face_uv_to_direction()
cell_uv_bounds()
cell_center_direction()
cell_corner_directions()
parent()
children()
neighbor()
```

Cross-face neighbor lookup samples an infinitesimal point outside the cube face edge, then re-addresses it through the same canonical direction mapping. No hand-written 24-edge lookup table is needed.

---

## 4. Quadtree invariants

Every non-root cell has exactly one parent. Every non-max-LOD cell has exactly four children.

Child coordinates:

```text
(2x,   2y)
(2x+1, 2y)
(2x,   2y+1)
(2x+1, 2y+1)
```

Same-level neighbor queries preserve LOD across cube-face boundaries.

Focused tests verify that adjacent same-level cells:

```text
have distinct stable identities
remain on the same LOD
are reciprocal through one of the neighbor edges
share the same two geometric edge corners
```

---

## 5. LOD policy

`SurfaceLodPolicy` v1 contains:

```text
min_lod
max_lod
refine_ratio
coarsen_ratio
minimum_distance_m
max_leaf_cells
```

Hysteresis invariant:

```text
coarsen_ratio < refine_ratio
```

Approximate cell edge scale:

```text
edge_m ≈ planet_radius × (π/2) / 2^lod
ratio  = edge_m / distance(observer, cell_surface_center)
```

A cell that was not split previously refines at `refine_ratio`. A subtree that was already split stays split until it drops below `coarsen_ratio`.

This intentionally belongs to presentation/representation selection. It is observer-dependent but does not alter GeoSample, PlanetDefinition, FeatureGraph or procedural world truth.

Policy validation also rejects a `max_leaf_cells` budget incapable of representing the requested `min_lod` over all six roots.

---

## 6. Selection determinism and performance

`SurfaceLodSelector.select_cells()` always starts from the same six roots and traverses children in canonical order.

Output includes:

```text
leaves[]
leaf_count
max_selected_lod
selection_hash
leaf_budget
```

The first implementation used a linear scan over all previous leaves for every candidate to answer whether the cell had descendants in the previous frame. Exact-engine fly-in exposed this as near-O(N²) behavior around 1000+ leaves.

Before handoff it was replaced with a precomputed ancestor-token index:

```text
previous leaves
→ ancestor identity index
→ O(1) previous_has_descendant(cell)
```

Stable cell identity lookup also has a fast `identity_token()` path for already validated/generated cells, avoiding repeated checksum/SHA work in hot loops.

After the optimization, the complete Linux focused runner executes in roughly 16 seconds in the isolated harness instead of timing out in multi-minute runs.

---

## 7. Cell lifecycle

G2 introduces a renderer-neutral lifecycle:

```text
REQUESTED
    ↓
BUILDING
    ↓
ACTIVE
    ↓
RETIRING
    ↓
removed
```

`reconcile(desired_cells)` creates requested cells and marks no-longer-desired cells retiring.

A retiring cell that is desired again:

```text
has active artifact → ACTIVE
no active artifact  → REQUESTED
```

The lifecycle does not own Thread, Node, Mesh or cache objects. Future scheduler/renderer code can attach those concerns outside the state machine.

The fly-in lab/tests use safe handoff ordering:

```text
1. request/build/activate incoming cover
2. keep old cover RETIRING meanwhile
3. release retiring cover only after incoming cells are ACTIVE
```

---

## 8. LOD is not world truth

A focused regression samples the same body-fixed point through the accepted G0 `GeoKernel` before and after addressing it at:

```text
LOD 0
LOD 2
LOD 5
LOD 9
LOD 14
```

The resulting `GeoSample` is byte/dictionary-equivalent and the same semantic surface-height field remains `12.5`.

Therefore:

```text
LOD changes representation selection
LOD does not change canonical geography
```

---

## 9. Debug lab

Scene:

```text
res://scenes/labs/procedural/g2_planetary_cells_lab.tscn
```

Controls:

```text
W / S    lower / raise altitude
A / D    change longitude
Q / E    change latitude
```

The lab renders adaptive cell boundaries through `ImmediateMesh`. LOD is color-coded and HUD shows:

```text
altitude
leaf count
max LOD
selection hash
```

All renderer/Camera3D code is isolated under `scripts/labs/`; G2 core source hygiene explicitly forbids renderer/Camera dependencies.

Headless scene startup on the exact double build passes.

---

## 10. Exact-engine isolated evidence

Engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Results:

```text
cold editor import:                    PASS
G2 planetary cells + LOD:              PASS — 16,190 assertions
G2 fly-in/out LOD continuity:          PASS — 2,412 assertions
G2 debug lab headless launch:          PASS
focused Linux runner:                  PASS
focused runner wall time in harness:   ~16 s
```

The seam suite exhausts all cells through LOD3 and additionally probes all six face boundaries at LOD4, LOD8 and LOD12.

Fly-in/out verifies:

```text
50,000 km → surface → 50,000 km
bounded leaf budget
valid non-overlapping leaf cover
progressive refinement near surface
no catastrophic coarsening during fly-in
no explosive growth during fly-out
REQUESTED/BUILDING/ACTIVE/RETIRING handoff
retired cell reclamation
```

---

## 11. Runners

Focused:

```text
RUN_G2_PLANETARY_CELLS_TESTS.ps1
RUN_G2_PLANETARY_CELLS_TESTS.sh
```

Full Windows gate:

```text
RUN_G2_FULL_ACCEPTANCE.ps1
```

The full gate runs:

```text
G1 focused dependency gate
G2 focused gate
existing full world/core regression
Breakpoint runtime :9081 noise audit
git diff --check vs feature/g1-geodesy-body-shape
```

---

## 12. Acceptance dependency

G2 is implemented on top of the current G1 candidate because the user explicitly requested the next stage before the pending independent G1 full-checkout acceptance was reported.

Therefore:

```text
G2 code status: IMPLEMENTED CANDIDATE
G2 acceptance:  BLOCKED until dependency/full-checkout evidence is green
```

A successful `RUN_G2_FULL_ACCEPTANCE.ps1` on the real checkout provides the required dependency-focused checks and full regression evidence for this stack.

---

## 13. Next stage after acceptance

```text
G3 — Mega Casual Macro Surface
feature/g3-casual-macro-surface
```

G3 may consume `SurfaceCellKey` and selected leaves to decide sampling density, but it must generate one continuous semantic world independent from cell boundaries and LOD.
