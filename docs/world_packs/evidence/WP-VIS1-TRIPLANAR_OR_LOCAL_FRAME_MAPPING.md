# WP-VIS1 — TRIPLANAR_OR_LOCAL_FRAME_MAPPING evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `890292539cd6d169e221bafd05296f99887b0b33`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless)

## Scope

Fifth milestone: diagnostic mapping derived from fixture-local frames instead
of global world axes. Changes:

- `scripts/world_packs/labs/surface_material_lab_fixtures.gd` — new
  registry math: `local_direction(fixture, world_direction)` (world→local via
  inverse basis) and `triplanar_weights_local(fixture, world_normal)` (blend
  weights from |local normal| components only).
- `scripts/world_packs/labs/surface_material_lab.gd` — real surface materials
  now use Godot `uv1_triplanar` (projection planes from node LOCAL axes)
  with a runtime-generated asset-free 8x8 checker `ImageTexture`; new
  `report_local_frame_mapping(fixture_id)` API returning local normal,
  roundtrip, local triplanar weights and triplanar-enabled flag.
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` — per-surface
  `_check_local_frame_mapping`: triplanar flag on, world→local roundtrip
  equals the declared local normal, and orientation-independence proof —
  rotating the whole fixture by (11°, 37°, 0°) leaves the local-frame
  triplanar weights unchanged (is_equal_approx).
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` —
  structural tests for the registry math, runtime checker generation (no
  load/preload), triplanar wiring and the orientation-independence check.

Presentation-only preserved; no production terrain/Matter/collision/ECO
changes.

## Validation actually run on tested_head 89029253

1. `python -m pytest tests/world_packs/material_lab -q` → **28 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=7 markers=0`, exit 0
   (incl. triplanar roundtrip + rotation-invariance proofs for all 7
   fixtures).

## Next

Milestone `FIDELITY_SWITCH_FIXTURE`: presentation fidelity switching on the
lab fixtures.
