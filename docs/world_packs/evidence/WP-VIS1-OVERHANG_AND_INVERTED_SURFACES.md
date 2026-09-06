# WP-VIS1 — OVERHANG_AND_INVERTED_SURFACES evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `886922bcc34baacdf02cc138fe5192d8f362954f`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless)

## Scope

Third milestone: real overhang and inverted/ceiling surfaces enabled through
the descriptor-driven `ENABLED_SURFACE_MILESTONES` mechanism. Changes:

- `scripts/world_packs/labs/surface_material_lab.gd` — added
  `OVERHANG_AND_INVERTED_SURFACES` to `ENABLED_SURFACE_MILESTONES`.
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` —
  `EXPECTED_SURFACES` extended with `overhang` and `inverted_ceiling`.
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` —
  expectations updated; new wiring test for the enabled milestone; sphere
  fixture still excluded from real surfaces.

Down-facing coverage is proven by the self-check orientation classes:
overhang world normal `(0, -0.707, -0.707)`, ceiling `(0, -1, 0)`.

Presentation-only preserved; no production terrain/Matter/collision/ECO
changes.

## Validation actually run on tested_head 886922bc

1. `python -m pytest tests/world_packs/material_lab -q` → **21 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=5 markers=1`, exit 0.

## Next

Milestone `SPHERE_OR_IRREGULAR_FIXTURE`: enable the sphere fixture and add
an irregular-rock-shaped variant if needed.
