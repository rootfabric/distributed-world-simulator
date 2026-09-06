# WP-VIS1 — SPHERE_OR_IRREGULAR_FIXTURE evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `2f6d4bae455e52c175375ef64e4801938e999353`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless)

## Scope

Fourth milestone: sphere and irregular rock fixtures as real surfaces. Changes:

- `scripts/world_packs/labs/surface_material_lab_fixtures.gd` — new
  `irregular_rock` descriptor (shape `irregular_rock`, probe normal the
  pre-normalized diagonal (1,1,1)/sqrt(3), rotation (-20, 35, 10) so no
  world axis is privileged); REQUIRED_IDS extended to 7 fixtures.
- `scripts/world_packs/labs/surface_material_lab.gd` —
  `SPHERE_OR_IRREGULAR_FIXTURE` enabled; new deterministic `_make_irregular_rock()`
  ArrayMesh builder: a 24x16 sphere displaced along vertex directions by a
  smooth trigonometric function (no randomness, no global axis bias),
  non-uniformly scaled by node scale.
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` —
  `EXPECTED_SURFACES` now all 7 fixtures; irregular rock carries no fixed
  orientation class (genuinely arbitrary diagonal probe).
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` —
  new fixture in required ids/milestones, determinism test (no randf/randi in
  the rock builder), diagonal probe guard.

Presentation-only preserved; no production terrain/Matter/collision/ECO
changes.

## Validation actually run on tested_head 2f6d4bae

1. `python -m pytest tests/world_packs/material_lab -q` → **25 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=7 markers=0`, exit 0.

## Next

Milestone `TRIPLANAR_OR_LOCAL_FRAME_MAPPING`: diagnostic mapping on the
surfaces derived from local frames instead of global world axes.
