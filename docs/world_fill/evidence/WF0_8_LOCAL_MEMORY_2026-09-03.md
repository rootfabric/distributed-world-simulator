# WF0.8 Local World Memory — Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\world-fill-r1` (branch
`feature/world-fill0-noncanonical-world-enrichment-r1`, base `0ab59369` WF0.7)

Deliverables:
- `scripts/world_fill/memory/world_fill_local_memory.gd` — local "I was
  here" layer: observed/local events (VISIT, DIG_SUCCESS, HANDOFF_OBSERVED,
  PHOTO_CAPTURED, LOCAL_NOTE) become crumbs stored ONLY under
  `user://world_memory/<memory_id>.json`; note text sanitized (newlines
  flattened, 120-char cap); budget `MAX_CRUMBS = 128`, oldest evicted;
  `server_synced: false` is a permanent report field;
- `tests/world_fill/test_wf0_8_local_memory.gd` — 7 scenario groups;
- `RUN_WORLD_FILL_WF0_8_TESTS.ps1` — chained runner (WF0.1 → WF0.8 → demo);
- demo `_build_local_memory()` loads the `demo_session` memory, records a
  visit, saves, prints `WORLD_FILL_LOCAL_MEMORY`.

Validation (runner `RUN_WORLD_FILL_WF0_8_TESTS.ps1`, all steps PASS):
1. event-derived crumbs: all four observed event types create their crumbs;
2. note sanitization: newlines flattened, note crumb typed local_note;
3. budget: 140 recorded → exactly 128 kept;
4. save/load roundtrip through user:// preserves crumb count and types;
5. local-only: storage path under `user://world_memory/`,
   `server_synced=false`;
6. fail-soft: missing file loads as empty (false, no error); unknown events
   create no crumb;
7. cleanup: clear_storage removes the file; reload yields empty memory.
Regression guards WF0.1-WF0.7 PASS. Demo: counters + `LOCAL_MEMORY=1`
(first demo session visit persisted), sentinel `WORLD_FILL_DEMO_READY`.

One test-side parse defect was fixed during validation (type inference on a
dynamic RefCounted call). A stray Godot editor process from an earlier
aborted run held the breakpoint_mcp port and was killed before the clean
pass; it did not affect validation results.

## Constitutional gates

- CANON-INDEPENDENT: crumbs are cosmetic memories; deleting them cannot
  change any canonical outcome.
- NO-NEW-WRITER: user:// local storage only; explicitly NOT a persistence
  owner of world truth; server persistence out of scope per roadmap.
- FAIL-SOFT: missing/corrupt files, unknown events — all degrade, no errors.
- DETERMINISTIC-WHEN-CLAIMED: crumb ordering is insertion/tick ordered with
  stable eviction.
- BUDGETED: 128 crumbs, asserted.
- DEMO-VISIBLE: demo persists and reports its visit memory.
- LICENSE-CLEAN: no third-party content.

## Scope note

Staged paths: `scripts/world_fill/`, `tests/world_fill/`,
`RUN_WORLD_FILL_WF0_8_TESTS.ps1`, `docs/world_fill/`.
