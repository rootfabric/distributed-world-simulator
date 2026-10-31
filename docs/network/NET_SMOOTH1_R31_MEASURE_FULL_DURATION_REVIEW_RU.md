# NET-SMOOTH1 R31 full GUI measure window — reviewer narrow repair

## Exact scope
- Parent frozen HEAD: `3079dc6fb1785156718f48385276445e47ea19f3` (PR #782).
- No production Godot GDScript, network authority, M6 checkpoint or analysis thresholds changed.
- Only `tools/net_smooth1/run_net_smooth1.py` clock placement, source falsifiers, exact CI branch trigger/ancestor fences, this note.
- PR #782 re-targeted from `main` to immediate network stack base PR #780 to avoid a 198-file misleading diff; no rebase, no merge.

## Review finding
`r31-reconnect-roundtrip` intentionally runs A primary→secondary, B reconnect while A is remote, and A secondary→primary *before* normative measurement. A `measure.start` marker is emitted **after** those functional stages. But the `standard_phase_loop()` duration loop uses a pre-stages `started=time.monotonic()` timestamp:
```python
while time.monotonic() - started < args.duration:
```
If stage work takes 30 seconds in a nominal 120s run, only ~90s of normatively measured movement follows. The fail-closed analyzer should correctly mark this INCONCLUSIVE. A slow enough r31 stage could skip the measured loop altogether. This is a duration/coverage bug, separate from the already fixed planned-reconnect CONNECTED false alarm.

## Minimal correction
Reset `started=time.monotonic()` immediately **after** `measure.start` at the end of the functional r31 stages, before invoking `standard_phase_loop()`. Keep all other scenario clocks, standalone 120s movement coverage, exact 25/50/100ms thresholds, and M6 untouched. A source negative mutant removes the reset and must fail.

## Mandatory gates
1. Source contracts (including negative mutant) on this branch.
2. Pinned Godot 4.7.1 double Windows/Linux exact inherited suites on this branch.
3. Fresh real Windows two-client Earth+Quaternius `--scenario r31-reconnect-roundtrip --duration 120` ×3. Confirm *all* runs have >=108s of process-local normative measure coverage, complete END/no-loss traces, correct authority roundtrip and B reconnect.
4. Run normative analyzer and report GUI p99/p99.9/max for each client **without threshold waivers**. p99 >25ms = FAIL.
5. Keep Project Control registry-generation-rotation (PR #783) and sync durable-drain Work Order distinct.

**Verdict:** TEST/HARNESS_NARROW_CANDIDATE; runtime/GUI acceptance pending. No merge into parent or main until independent gates are complete.
