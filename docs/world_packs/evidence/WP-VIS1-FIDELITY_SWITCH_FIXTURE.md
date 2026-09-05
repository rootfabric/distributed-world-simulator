# WP-VIS1 — FIDELITY_SWITCH_FIXTURE evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `9a543e9b72bd89aaaa381da586fe53e64659d67e`
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless)

## Scope

Sixth milestone: presentation fidelity switching on the lab fixtures. Changes:

- `scripts/world_packs/labs/surface_material_lab.gd` —
  `FIDELITY_LEVELS = ["preview", "full"]` (preview = flat diagnostic color,
  full = local-frame triplanar checker detail); `-- --fidelity=<level>`
  command-line selection; `report_fidelity()` and `apply_fidelity(level)`
  automation API. Fidelity changes material detail only: transforms,
  rotation data and the fixture registry are untouched, so orientation truth
  can never depend on presentation fidelity.
- `scripts/world_packs/labs/surface_material_lab_self_check.gd` —
  `_check_fidelity_switch`: default is full; preview drops triplanar on all
  7 surfaces; unknown level `ultra` is rejected; full restores triplanar;
  world normals are proven identical across all switches.
- `tests/world_packs/material_lab/test_surface_material_lab_scaffold.py` —
  structural tests: fidelity API surface, `apply_fidelity` forbidden from
  touching position/rotation/registry, self-check safety proofs present.

Presentation-only preserved; no production terrain/Matter/collision/ECO
changes.

## Validation actually run on tested_head 9a543e9b

1. `python -m pytest tests/world_packs/material_lab -q` → **30 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=7 markers=0`, exit 0
   (incl. fidelity switch proofs).

## Next

Milestone `HEADLESS_AND_GRAPHICAL_EVIDENCE_READY`: publish headless evidence
and graphical capture evidence for the lab, then set READY_FOR_INTEGRATION.
