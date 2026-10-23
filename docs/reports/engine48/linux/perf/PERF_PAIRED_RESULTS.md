# ENGINE48 Linux — Paired PERF: Godot 4.8-beta1-double vs 4.7.1-stable-double (R1)

- Date: 2026-10-21 (UTC)
- Host: shared Ubuntu 22.04 box, 1280x720 gl_compatibility under Xvfb (llvmpipe software GL)
- Worktrees: 4.8 → `worktrees/engine48-linux-guards` (repair branch HEAD); 4.7.1 → `worktrees/bench-471-mvp5` (throwaway A/B copy)
- Scenario: M7 networked playground, headless dedicated server + 2 graphical gl_compatibility clients (`--network-debug-stay-open`), LOCAL network profile, 30 s settle + 180 s steady state
- Samples: 3 runs per engine (ports 24701-24703 / 24711-24713), sequential, identical command lines

## Paired table (server-side, from SERVER_HEALTH + m7-result JSON)

| metric | 4.8 r1 | 4.8 r2 | 4.8 r3 | 4.7.1 r1 | 4.7.1 r2 | 4.7.1 r3 |
|---|---|---|---|---|---|---|
| connected_peers (max) | 2 | 2 | 2 | 2 | 2 | 2 |
| rejections | 0 | 0 | 0 | 0 | 0 | 0 |
| hard_stalls | 0 | 0 | 0 | 0 | 0 | 0 |
| soft_stalls | 0 | 0 | 0 | 0 | 0 | 0 |
| script_errors | 0 | 0 | 0 | 0 | 0 | 0 |
| moves_total | ~6.2-6.4k | ~6.2-6.4k | ~6.2-6.4k | ~6.2-6.4k | ~6.2-6.4k | ~6.2-6.4k |
| worst cumulative watchdog max_elapsed_ms | 667 | 678 | 713 | 711 | 719 | 799 |
| server RSS last, KB | 65163 | 65239 | 65215 | 63413 | 63343 | 63330 |
| cpu_seconds_total (3 procs, ~180 s) | 1445.6 | 1425.5 | 1468.3 | 1430.9 | 1438.2 | 1486.5 |

## Client FPS (`--print-fps`, "Project FPS: N", both clients interleaved)

| engine | samples/run | p50 | p95 | mean |
|---|---|---|---|---|
| 4.8 r1/r2/r3 | 397/395/395 | 16/16/16 | 18 | 16.3/15.7/16.4 |
| 4.7.1 r1/r2/r3 | 394/390/392 | 16/16/16 | 18 | 15.9/15.9/16.2 |

## Engine means (3 runs each)

| metric | 4.8 beta1 | 4.7.1 stable | delta |
|---|---|---|---|
| worst server stage max (cumulative watchdog) | 686.0 ms | 743.0 ms | **−7.7 % (4.8 better)** |
| cpu_seconds_total | 1446.4 | 1451.9 | −0.4 % (parity) |
| server RSS | 65206 KB | 63362 KB | +2.9 % (mild increase, no monotonic growth inside runs) |
| client FPS p50 | 16 | 16 | parity (llvmpipe-bound) |

## Interpretation and caveats

1. **No client/server throughput or stability regression attributable to 4.8**: identical peer counts, zero rejections/stalls/script errors, equal move throughput, and a *better* worst-case server stage elapsed in every paired triple.
2. `stall_watchdog.max_elapsed_ms` reported here is **cumulative-since-start**; the final value equals the worst single stage of the whole run, so p50/p95/p99 windowing is not applicable on this snapshot's tooling.
3. Absolute FPS (16) is **llvmpipe-bound** at 1280x720; these numbers compare engines against each other, not GPU-class performance.
4. **NET-SMOOTH1 server p99 ≤ 25 ms is not directly measurable on this snapshot** — the net_smooth1 instrumented branch is not merged here. The paired watchdog/stall data shows no 4.8 regression of the class that produced the Windows architecture finding (~39.8-41.3 ms); that finding remains a separate pre-existing item.
5. Server RSS +2.9 % on 4.8 is stable across runs (no leak-shaped growth within 3.5 min runs).
6. Raw inputs: `perf/godot{48,471}-r{1,2,3}.metrics.json`, `perf/godot48-r1/proc.log` (+ siblings), parsed summary in `perf/perf-summary.json`.

VERDICT(PERF, paired, this environment): **NO 4.8 REGRESSION FOUND** (3+3 pairs).
