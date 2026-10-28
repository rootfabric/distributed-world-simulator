# WP-VIS1 — HEADLESS_AND_GRAPHICAL_EVIDENCE_READY evidence

- Track: `WP-VIS1` (branch `work/world-packs-vis1-material-lab-r1`)
- Implementation commit (tested_head): `b13afce094fbbdcfd134ce094a50283cbedfce68` (+ uid follow-up `58e968620f579d52ad75f7fe0369fdbff548b317`, state-only class)
- Date (UTC): 2026-09-05
- Environment: Windows, pwsh, Python 3.11, Godot 4.7.1.stable.double.custom_build (headless + real renderer capture)

## Scope

Seventh and final declared milestone: durable headless + graphical evidence
for the lab. Changes:

- `scripts/world_packs/labs/surface_material_lab_capture.gd` — graphical
  capture SceneTree script: loads the lab, renders frames on the real
  renderer, captures the viewport at full fidelity, switches to preview and
  captures again, then quits with `SURFACE_MATERIAL_LAB_CAPTURE=PASS`.
- Evidence artifacts (this commit):
  - `docs/world_packs/evidence/WP-VIS1-lab-full-fidelity.png` (174648 bytes)
  - `docs/world_packs/evidence/WP-VIS1-lab-preview-fidelity.png` (106849 bytes)
  - `docs/world_packs/evidence/WP-VIS1-headless-self-check.log` (UTF-8, written via python, never PowerShell redirect)

Both PNGs verified: valid PNG signature, non-trivial distinct pixel data,
and different sizes (full fidelity carries the triplanar checker detail).

## Validation actually run on tested_head b13afce0

1. `python -m pytest tests/world_packs/material_lab -q` → **31 passed**.
2. Godot headless self-check →
   `SURFACE_MATERIAL_LAB_SELF_CHECK=PASS surfaces=7 markers=0`, exit 0.
3. Graphical capture (real renderer, non-headless):
   `godot --path . --script res://scripts/world_packs/labs/surface_material_lab_capture.gd -- --out-dir=res://docs/world_packs/evidence/`
   → `SURFACE_MATERIAL_LAB_CAPTURE=PASS`, exit 0, both PNGs written.
4. Predecessor regression `python -m pytest tests/world_packs/test_parallel_controller.py -q` → **5 passed** (run on this branch earlier at 6e5b93ca; controller verify green at every checkpoint).

## Workstream summary

All seven declared milestones complete:

1. GENERIC_LAB_SCAFFOLD
2. HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES
3. OVERHANG_AND_INVERTED_SURFACES
4. SPHERE_OR_IRREGULAR_FIXTURE
5. TRIPLANAR_OR_LOCAL_FRAME_MAPPING
6. FIDELITY_SWITCH_FIXTURE
7. HEADLESS_AND_GRAPHICAL_EVIDENCE_READY

The lab proves: arbitrary-orientation fixtures (up/side/down + arbitrary
diagonal probe), local-frame mapping (uv1_triplanar + registry math with
rotation-invariance proofs), fidelity switching that never touches
orientation truth. Presentation-only throughout: no production terrain,
Matter, canonical collision or ECO paths were modified.

Status set to READY_FOR_INTEGRATION per protocol (all milestones complete,
focused validation green, scope violations 0, blockers empty, evidence
published). Worker does not self-merge; integration proceeds through the
controller/integrator gate.
