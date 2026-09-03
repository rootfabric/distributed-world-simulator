# WF0.7 Digging Playground Composition — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (branch
`feature/world-fill0-noncanonical-world-enrichment-r1`, base `a5debbe7` WF0.6)

Deliverables:
- `scripts/world_fill/composition/digging_playground.gd` — the integrated
  presentation stand: ambience (WF0.4 clock preset), ground, cosmetic seam
  marker (10 emissive segments), dig-pit presentation (floor disc + 8 rim
  rocks; a visual scar, not digging logic), starter props scatter (WF0.2,
  384 budgeted instances), observed dig-site scars (WF0.3, 3 events),
  two POIs (WF0.6: mining_camp + landing_site), two signs (Label3D), and a
  spectator camera path cycling six named bookmarks
  (spawn/outpost/dig_site/seam/handoff/horizon);
- `scenes/labs/world_fill/digging_playground.tscn` — lab scene root;
- `tests/world_fill/test_wf0_7_playground.gd` — 4 scenario groups;
- `RUN_WORLD_FILL_WF0_7_TESTS.ps1` — chained runner (WF0.1 → WF0.7 tests,
  headless launch of BOTH lab scenes).

Validation (runner `RUN_WORLD_FILL_WF0_7_TESTS.ps1`, all steps PASS):
1. composition contents: ambience=clear, scatter>0, scars≥3, pois≥1,
   signs≥2, seam segments exact, pit floor+rim present;
2. camera path: exactly six bookmarks, spectator camera attached;
3. deterministic rebuild: two identical builds produce identical reports;
4. no new implementation surface: zero collision nodes, zero replication
   nodes anywhere in the composition.
One parse defect was fixed during validation (typed locals for dictionary
lookups). Regression guards WF0.1-WF0.6 PASS.
Headless scene runs:
- `digging_playground.tscn`: `WORLD_FILL_PLAYGROUND_AMBIENCE=clear`,
  `SCATTER=384`, `SCARS=3`, `POIS=2`, sentinel
  `WORLD_FILL_DIGGING_PLAYGROUND_READY`;
- `world_fill_demo.tscn`: all prior counters + `WORLD_FILL_DEMO_READY`.

## Constitutional gates

- CANON-INDEPENDENT: the playground is a pure presentation stand; the
  roadmap phrase "diggable terrain" is represented by the cosmetic dig pit
  and observed-event scars — no terrain mutation implementation exists here.
- NO-NEW-WRITER: consumes only WF0.x presentation components.
- FAIL-SOFT: composition degrades with its components (each fail-soft).
- DETERMINISTIC-WHEN-CLAIMED: rebuild-identical reports asserted.
- BUDGETED: inherits scatter budget (384 ≤ cap), 2 POIs ≤ 32, 1 env+1 light.
- DEMO-VISIBLE: this IS the visible stand; headless counters + sentinel.
- LICENSE-CLEAN: primitives and Label3D only.

## Scope note

Staged paths: `scripts/world_fill/`, `tests/world_fill/`, `scenes/labs/world_fill/`,
`RUN_WORLD_FILL_WF0_7_TESTS.ps1`, `docs/world_fill/`.
