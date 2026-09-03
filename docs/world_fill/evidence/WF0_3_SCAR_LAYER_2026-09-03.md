# WF0.3 Surface Scars / Decals — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (branch
`feature/world-fill0-noncanonical-world-enrichment-r1`, base `1f9342c2` WF0.2)

Deliverables:
- `scripts/world_fill/decals/world_fill_scar_layer.gd` — presentation-only
  scar layer: `record_event(observed_event, observed_tick)` maps observed
  event types (`DIG_IMPACT`, `DIG_SUCCESS`, `MATERIAL_EXPOSED`,
  `BUILD_COMMIT`, `CONTACT_TRACE`, `COMMAND_REJECTED`; unknown → generic
  `surface_wear`) to cosmetic marks (alpha-blended quads, shadows off);
- bounded budget: `MAX_ACTIVE_DECALS = 64`, oldest evicted first;
- bounded lifetime: `age_out(current_tick)` removes strictly-older-than
  `LIFETIME_TICKS = 3600` presentation ticks;
- `COMMAND_REJECTED` marks are debug-only (hidden by default, toggled by
  `set_debug_marks_visible`) per the roadmap's rejected-action feedback;
- `tests/world_fill/test_wf0_3_scar_layer.gd` — 6 scenario groups;
- `RUN_WORLD_FILL_WF0_3_TESTS.ps1` — chained runner (WF0.1 → WF0.2 → WF0.3
  → demo);
- demo `_build_scar_history()` records 3 observed events and prints
  `WORLD_FILL_SCARS_ACTIVE`.

Validation (runner `RUN_WORLD_FILL_WF0_3_TESTS.ps1`, all steps PASS):
1. `editor_import_parse`: PASS; `WorldFillScarLayer` registered cleanly.
2. `wf0_1_dressing_contract`: PASS (regression guard).
3. `wf0_2_prop_scatter`: PASS (regression guard).
4. `wf0_3_scar_layer`: PASS — event→family mapping, budget eviction of the
   oldest scar at 64+, boundary-exact lifetime semantics (a scar exactly at
   `LIFETIME_TICKS` survives; one tick later it is freed), fail-soft unknown
   events, debug marks hidden by default and visible in debug mode, report
   exposes only presentation counters. One test-side boundary-arithmetic
   defect was found and fixed during validation (test expected eviction at
   the exact-lifetime tick; the roadmap requires bounded lifetime, the
   implementation keeps strictly-older-than semantics and the test now
   pins that boundary explicitly).
5. `world_fill_demo_headless`: PASS — `WORLD_FILL_SCATTER_INSTANCES=384`,
   `WORLD_FILL_SCARS_ACTIVE=3`, sentinel `WORLD_FILL_DEMO_READY`.

## Constitutional gates

- CANON-INDEPENDENT: scars are visual nodes only; removing the layer cannot
  change any canonical outcome.
- NO-NEW-WRITER: the layer only consumes observed events; it owns no truth,
  no persistence, no replication.
- FAIL-SOFT: unknown event types degrade to generic `surface_wear`; missing
  position/normal fields default safely.
- DETERMINISTIC-WHEN-CLAIMED: event application is order-deterministic with
  stable eviction/aging rules (no RNG involved).
- BUDGETED: 64 active marks cap, asserted; marks cast no shadows.
- DEMO-VISIBLE: scar history observable in the demo scene with a counter.
- LICENSE-CLEAN: procedural primitives only, no third-party content.

## Scope note

Staged paths: `scripts/world_fill/`, `tests/world_fill/`,
`RUN_WORLD_FILL_WF0_3_TESTS.ps1`, `docs/world_fill/`.
