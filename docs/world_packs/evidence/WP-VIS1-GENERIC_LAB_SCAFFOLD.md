# WP-VIS1 — GENERIC_LAB_SCAFFOLD evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `11887fab929e24310394d2a868f64d2084f9c568`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (double build, headless)

## Scope

Presentation-only, asset-free generic Surface Material Lab scaffold. Files:

- `scenes/labs/world_packs/surface_material_lab.tscn` — lab scene root wired to the lab script.
- `scripts/world_packs/labs/surface_material_lab.gd` — lab frame (neutral environment, reference grid backdrop, camera) plus scaffold markers; real oriented surfaces are built by later milestones through the same `_build_surface` entry point.
- `scripts/world_packs/labs/surface_material_lab_fixtures.gd` — fixture descriptor registry: six fixtures (horizontal_plane, slope_45, vertical_wall, overhang, inverted_ceiling, sphere_fixture) with explicit fixture-local surface normals, rotations, diagnostic colors and the milestone that instantiates each real surface.
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` — headless SceneTree self-check (registry validation + scene build proof).
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` — structural pytest suite.

No production terrain, Matter, canonical collision or ECO paths were touched. The registry contains no `built_in_milestone: GENERIC_LAB_SCAFFOLD` fixture — the scaffold only places markers and validates descriptors.

## Anti-Y-up design notes

- Every fixture declares `surface_normal_local` + `rotation_degrees`; world normals are computed via `Basis.from_euler`, never from a global up assumption.
- Registry self-check requires orientation coverage: at least one up-facing, one side-facing and one down-facing world normal, so a hidden Y-up assumption fails the scaffold itself.
- The lab script uses `Vector3.UP` only as a rendering fallback for marker arrow geometry; mapping/build code derives orientation exclusively from descriptors.

## Validation actually run on tested_head 11887fab

1. `python -m pytest tests/world_packs/material_lab -q` → **17 passed**.
2. Godot headless self-check:
   `godot --headless --path . --script res://scripts/world_packs/labs/surface_material_lab_self_check.gd`
   → `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS markers=6`, exit code 0.
   Reported world normals: horizontal (0,1,0); slope45 (-0.707,0.707,0); wall (0,0,-1); overhang (0,-0.574,-0.819); ceiling (0,-1,0); sphere probe (1,0,0).
3. Predecessor regression `python -m pytest tests/world_packs/test_parallel_controller.py` → passed (as part of a combined run: 68 passed, 1 unrelated failure `test_library_contract.py::test_local_missing_symlink_and_corruption` caused by Windows symlink privilege WinError 1314 — environment limitation, not related to this workstream).

## Next

Milestone `HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES`: instantiate real oriented surfaces (horizontal, 45-degree slope, vertical wall) via the existing `_build_surface` entry point.
