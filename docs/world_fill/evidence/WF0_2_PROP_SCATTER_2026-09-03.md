# WF0.2 Deterministic Prop Scatter — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`
(`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`)

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (branch
`feature/world-fill0-noncanonical-world-enrichment-r1`, base `37c00287` WF0.1)

Deliverables:
- `scripts/world_fill/scatter/world_fill_prop_scatter.gd` — native
  `MultiMeshInstance3D` scatter consuming the WF0.1 dressing decision;
  budget table `none=0 / sparse=24 / moderate=96 / dense=288` per family,
  documented global cap 1728; per-family RNG seeded from
  `hash(determinism_key|family|base_seed)`;
- `tests/world_fill/test_wf0_2_prop_scatter.gd` — 5 scenario groups;
- `RUN_WORLD_FILL_WF0_2_TESTS.ps1` — runner (import → WF0.1 → WF0.2 → demo);
- demo `world_fill_demo.gd` extended with `_build_scatter()` feeding
  `WorldFillDressing.derive({surface_type="regolith", seed=0x57464C30})`.

Validation (runner `RUN_WORLD_FILL_WF0_2_TESTS.ps1`, all steps PASS):
1. `editor_import_parse`: PASS; `WorldFillPropScatter` registered cleanly.
2. `wf0_1_dressing_contract`: PASS (regression guard).
3. `wf0_2_prop_scatter`: PASS —
   - determinism: identical decision+seed → identical reports AND identical
     full MultiMesh transform arrays (12 components per instance compared);
   - budgets: every family count ≤ its band budget; total ≤ 1728 cap;
   - fail-soft: empty decision → zero instances, zero MultiMesh nodes;
   - no `CollisionObject3D`/`CollisionShape3D` anywhere in scatter output;
   - `clear_scatter()`/rebuild resets state completely.
4. `world_fill_demo_headless`: PASS —
   `WORLD_FILL_SCATTER_INSTANCES=384` (stones dense 288 + debris moderate 96,
   matches the budget table exactly) and sentinel `WORLD_FILL_DEMO_READY`.

Cross-process determinism (probe `artifacts/wf0_1_determinism_probe.gd`,
not committed): two independent Godot processes produced the identical
WF0.1 `determinism_key` `1642221827:42`, so scatter seeds derived from it are
stable across engine restarts as well.

## Constitutional gates

- CANON-INDEPENDENT: scatter is a child Node3D under the demo/lab scene only;
  deleting `world_fill/` cannot affect any canonical outcome.
- NO-NEW-WRITER: no authority/persistence owner; nothing replicated.
- FAIL-SOFT: empty/unknown decisions degrade to zero instances.
- DETERMINISTIC-WHEN-CLAIMED: proven in-process (tests) and cross-process (probe).
- BUDGETED: explicit per-band budget table + documented global cap, asserted.
- DEMO-VISIBLE: observable in `world_fill_demo.tscn` with instance-count print.
- LICENSE-CLEAN: procedural primitive meshes only, no third-party content.

## Scope note

Staged paths: `scripts/world_fill/`, `tests/world_fill/`,
`RUN_WORLD_FILL_WF0_2_TESTS.ps1`, `docs/world_fill/`. Plugins were NOT used
(native baseline first, per the scout order); editor-scatter adoption remains
a decision gated on the scout report.
