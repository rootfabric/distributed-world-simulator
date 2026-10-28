# WP-VIS1 — HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `6e5b93ca61d7dc67324a95b27b64162a728eb9c9`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless)

## Scope

Second milestone: real oriented horizontal / 45-degree slope / vertical wall
surfaces instantiated in the existing lab through the same `_build_surface`
entry point. Changes:

- `scripts/world_packs/labs/surface_material_lab.gd` — new
  `ENABLED_SURFACE_MILESTONES` list; `_ready` selects real surface vs marker
  via the descriptor's `built_in_milestone` (no ad-hoc id list). Real
  surfaces now also carry the `LocalNormal` indicator and a Label3D, both
  derived from the descriptor only.
- `scripts/world_packs/labs/surface_material_lab_fixtures.gd` — overhang
  rotation corrected from -125 to -135 degrees so its world normal
  `(0, -0.707, -0.707)` classifies honestly as down-facing under the lab's
  0.7/0.3 orientation thresholds (overhang still instantiates only in its
  own later milestone).
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` — now
  verifies exactly 3 real surfaces (`Fixture_*`) + 3 markers, per-fixture
  orientation classes against expectations, presence of `LocalNormal` on
  each surface, and that the lab `report_world_normal` API matches the
  registry normals.
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` —
  added structural tests: enabled-milestone wiring, self-check expectations
  limited to the enabled fixtures, overhang rotation guard.

Presentation-only preserved: no production terrain, Matter, canonical
collision or ECO paths touched.

## Validation actually run on tested_head 6e5b93ca

1. `python -m pytest tests/world_packs/material_lab -q` → **20 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=3 markers=3`, exit 0.
   World normals: horizontal (0,1,0); slope45 (-0.707,0.707,0); wall
   (0,0,-1); overhang (0,-0.707,-0.707); ceiling (0,-1,0); sphere probe
   (1,0,0).
3. Regression `python -m pytest tests/world_packs/test_parallel_controller.py -q` → **5 passed**.

## Next

Milestone `OVERHANG_AND_INVERTED_SURFACES`: enable real overhang and
inverted/ceiling surfaces (descriptors already registered) by adding the
milestone to `ENABLED_SURFACE_MILESTONES` and extending self-check
expectations.
