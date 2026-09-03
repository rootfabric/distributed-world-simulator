# WF0.4 Ambient World Clock / Atmosphere — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (branch
`feature/world-fill0-noncanonical-world-enrichment-r1`, base `7962078b` WF0.3)

Deliverables:
- `scripts/world_fill/ambience/world_fill_atmosphere.gd` — presentation
  atmosphere owning exactly one WorldEnvironment + one DirectionalLight3D;
  five presets (`clear`, `dust`, `storm`, `dawn`, `night`) covering sun
  direction/energy/color, ambient level, background, fog density/color,
  exposure and a wind-audio selector; `apply_clock(read_only_clock)` maps
  `day_fraction` deterministically over the closed clock-derived set
  {night, dawn, clear}; `dust`/`storm` are explicit overrides only;
- `tests/world_fill/test_wf0_4_atmosphere.gd` — 6 scenario groups;
- `RUN_WORLD_FILL_WF0_4_TESTS.ps1` — chained runner (WF0.1 → WF0.4 → demo);
- demo `_build_environment()` now delegates to the atmosphere
  (`apply_clock({day_fraction: 0.42})` → `clear`), replacing the hand-built
  environment; the `clear` preset reproduces the original demo lighting
  values exactly (bg 0.008/0.01/0.018, ambient 0.18/0.2/0.26 @0.45, sun
  -42°/-28° @1.7), so the visual baseline is continuous.

Validation (runner `RUN_WORLD_FILL_WF0_4_TESTS.ps1`, all steps PASS):
1. all five presets apply, one WorldEnvironment + one DirectionalLight3D;
2. clock mapping deterministic, all pinned boundaries (0/0.2/0.3/0.85/1.0)
   verified, including 0.84→clear vs 0.85→night;
3. closed-set invariant: sweeping day_fraction 0..1 never derives dust/storm;
4. explicit override works and the clock retakes control on the next tick;
5. fail-soft: unknown preset falls back to clear with `fallback_used=true`;
   empty clock defaults to mid-day clear without fallback flag;
6. report exposes only presentation keys and declares `presentation_only`.
Regression guards WF0.1/WF0.2/WF0.3 PASS; demo: `WORLD_FILL_AMBIENCE=clear`,
`WORLD_FILL_SCATTER_INSTANCES=384`, `WORLD_FILL_SCARS_ACTIVE=3`,
sentinel `WORLD_FILL_DEMO_READY`.

## Constitutional gates (WF0.4 non-goals respected)

- No movement penalties, no canonical temperature, no weather damage, no
  sleep rules, no authoritative storm state: the atmosphere writes only
  Environment/light properties and returns presentation dictionaries.
- CANON-INDEPENDENT / NO-NEW-WRITER: consumes a caller-supplied read-only
  clock projection; owns no truth, persistence or replication.
- FAIL-SOFT: unknown presets and empty clocks degrade, never error.
- DETERMINISTIC-WHEN-CLAIMED: pure function of clock input (no RNG).
- BUDGETED: one environment + one light node total; no per-frame allocations.
- DEMO-VISIBLE: ambience selector printed in the demo run.
- LICENSE-CLEAN: no third-party content.

## Scope note

Staged paths: `scripts/world_fill/`, `tests/world_fill/`,
`RUN_WORLD_FILL_WF0_4_TESTS.ps1`, `docs/world_fill/`.
