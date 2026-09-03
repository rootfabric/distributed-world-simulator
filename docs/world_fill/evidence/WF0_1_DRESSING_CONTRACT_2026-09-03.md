# WF0.1 Environmental Dressing Contract — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`
(`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`)

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (linked worktree of
`.git-store/repo.git`, branch `feature/world-fill0-noncanonical-world-enrichment-r1`)

Baseline before change:
- fresh headless `--import` in the worktree: PASS (exit 0);
- headless `world_fill_demo.tscn`: PASS (exit 0, sentinel
  `WORLD_FILL_DEMO_READY`, 0 error-pattern hits).

WF0.1 validation (runner `RUN_WORLD_FILL_WF0_1_TESTS.ps1`):
1. `editor_import_parse` (`--headless --editor --path . --quit`): PASS;
   `WorldFillDressing` registered as a global class without warnings.
2. `wf0_1_dressing_contract`
   (`--headless --script res://tests/world_fill/test_wf0_1_dressing_contract.gd`):
   PASS — 11 scenario groups, 0 failures:
   - determinism: identical inputs+seed → identical outputs;
   - seed sensitivity: different seed → different `determinism_key`;
   - read-only: descriptor deep-compares equal before/after derive;
   - no aliasing: mutating output leaves descriptor untouched;
   - graceful degradation: `{}` descriptor yields valid generic decision plus
     populated `degraded_inputs`;
   - surface mapping: metal → dense `industrial_scrap`, ice → `crystals`;
   - steep slope (60°): `boulders` keep `moderate`, `stones` demoted out;
   - moisture 0.9 suppresses `dry_branches`, moisture 0.05 on soil raises them;
   - ECO ground cover promotes `stones` one band;
   - ambience: `open_wind` / `underground_echo` / `thin_air_loop` selection;
   - decals: base + surface + wreckage tag with dedup; POI hints sane.
3. `world_fill_demo_headless`: PASS — sentinel `WORLD_FILL_DEMO_READY`
   present, no `SCRIPT ERROR`, no `: FAIL` markers.

Runner summary (machine-readable):
`artifacts/test-results/world-fill-wf0-1-summary.json` (not committed;
generated per-run).

## Constitutional gates

- CANON-INDEPENDENT: contract is pure derivation over caller-supplied
  descriptors; no canonical module references `world_fill/`.
- NO-NEW-WRITER: no authority/persistence owner introduced.
- FAIL-SOFT: missing producer fields degrade into `degraded_inputs`.
- DETERMINISTIC-WHEN-CLAIMED: proven by the test suite above.
- BUDGETED: density bands (`none/sparse/moderate/dense`) are the budget hook
  for WF0.2 scatter counts.
- DEMO-VISIBLE: contract feeds the existing `world_fill_demo.tscn` stand;
  WF0.2 will make it visually observable.
- LICENSE-CLEAN: no third-party content introduced.

## Scope note

Only world-fill-scoped paths were staged:
`scripts/world_fill/`, `tests/world_fill/`, `RUN_WORLD_FILL_WF0_1_TESTS.ps1`,
`docs/world_fill/`. Fresh-import `.uid` side effects for unrelated modules
(P7/SM1/ecology fixtures of the base tree) were left untracked on purpose.

This validates the contract semantics in one isolated double-Godot project
import, consistent with the WF0.0 evidence discipline. Network-dependent
plugin/asset acceptance remains governed by the scout work order and is not
claimed here.
