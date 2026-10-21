# ECO ARCH2 A14.6 R3.2.1 — Native frame-stall attribution (diagnostic)

Status: DRAFT, diagnostic-only; performance acceptance remains BLOCKED. Parent is PR #805 product `e33427a54cbdbeaba1e865c630b8ef076476444a`, TREE `f3520289b08b2e41b0c61beaa50a254208906bdd`. Base R3 PR #798 is `080fdbef...`; accepted `main` remains `aac301b9...`.

## Why separate from R3.2

Native Windows/Linux Exact and a fresh independent verifier are already running for frozen #805 HEAD. Keep their evidence anchored; DO NOT change the #805 branch, merge, force push, or claim CI completion on this follow-up.

## Attribution

The off-main worker finishes one exact complete global A5 -> A4 original-equivalent -> ADVANCE -> A6 tick; on completion the main thread performs a pool-task join and repeats `Runtime.validate(state)` before its one publication. The actual LAB `Workbench._process` then rebuilds the presentation snapshot. At 256 organisms portable observed ~786 ms main-poll peak (single exploratory run). The high cost may be from source validation, GDScript/worker scheduling contention, UI presentation, or a mix; do not assert a cause before timing.

R3.2.1 measures separately, without changing scheduling, authority, source admission, biology, or checkpoint bytes:

* `peak_background_poll_us` — maximum non-final return from `OffMain.advance` while CPU task executes (includes main-thread contention if present);
* `main_join_wall_us` — wait for already-completed task;
* `main_source_admission_wall_us` — whole-source `Runtime.validate(state)`, still executed on the MAIN thread to reject changed nested source;
* `main_complete_poll_wall_us` — complete worker result adoption, including join and validation;
* `main_pending_process_peak_wall_us`, `main_commit_process_wall_us` — measured real LAB GUI callback wall times, including snapshot rebuild on completed commit.

The scale profile preserves all mandatory sizes 4/32/96/256, one freshly launched native Godot process per size, full canonical state/hash and A8 serialized checkpoint parity. Timing fields are observational and excluded from canonical digests. No hard 30 ms deadline or throughput speedup claimed.

## Gates

1. Record #805 native Windows 256 exit status, stderr and peak working set on frozen e33427a5; distinguish crash/resource/runner from portable correctness.
2. Run R3.2.1 portable and native double attribution; report p50/p95/p99 for repeated GUI frames and per-phase peaks at each scale. A single exploratory peak is not a percentile.
3. Only after identifying the dominant source, make a separate narrow performance fix and independently verify source/owner cancellation, stale-source rejection, parity and no worker leak.
4. Do not merge #798/#805 or this branch as a smoothness fix while exact or performance gates are red or unknown.
