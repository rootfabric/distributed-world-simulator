# A14.7 R2 Stage E2 — deep-owned, fully verified CPU source (research only)

**STATUS: Draft / NO MERGE / Default OFF / LAB only.**
Direct frozen parent Stage E1 PR #847 `8ede5dc512eb0d0955ae4212743ef3b7893c33af`, TREE `20b343da7cccc06a6b9b9d387e96fa436d056f80`. Stage E1 rejected slower A5 PREPARE/ADVANCE COW and retained original Stage D code plus measured CPU profiler. Main remains `aac301b9a9a89e027f6d99864437eb750a4202ca`. No rebase, merge or force-push.

## Evidence and goal

Windows R1 RTX4060 real GUI p99 6.3–7.3ms, canonical tick n256 ~17.6s and backlog accumulates. Stage E1 portable profiling on frozen original A5 shows repeated public `Runtime.validate(source)` accounts for roughly **29%** of worker wall (n256 3.845s/13.101s), with repeated A5 source digest ~4.25%. Skipping public validation arbitrarily is UNSAFE with mutable nested Dictionaries, cancellation and hostile/moved source.

Goal E2: keep the real Controller/OffMain public entry fully safe while testing a **single deep-detached CPU-worker-owned source** and caching only the fact that it was FULLY validated at worker admission. Repeated expensive *structural* `Runtime.validate` can then be replaced by an exclusive identity/generation cursor lease INSIDE the worker, but ALL original signed outer cursor checks, options hash checks, and A5 and original global A4 nested digests remain. Both source and candidate receive mandatory full `Runtime.validate` before final worker acceptance. One global A4 and exact original reference. No CPU task publishes incomplete results.

## Strict trust and failure model

- New `ecology_owned_worker_source_r2e2_v1.gd` is allocated **inside WorkerThreadPool._compute**. It recursively deep-copies Controller-owned source and options into a detached instance, fully validates `Runtime.validate(source)`, preserves the immutable source hash/tick/options hash/A5 field+population fingerprint. No borrowed nested alias remains on the main thread.
- New `Runtime.resume_staged_global_tick` optional trailing `r2e_owned_cpu: RefCounted=null`. When null, it executes the EXACT prior `Runtime.validate(state)` before any step, no exception. When non-null, first require WORKER thread, exact expected owner-context Script path and its identity-bound current owned source/options/outer and A5 source anchors; all existing signed outer cursor and A5 public-source checksum checks still run. This exceptional API is NOT a general call-site optimization and not admissible from the GUI or direct untrusted service. No full checks disabled in A5 or A4.
- `OffMain.advance` trailing `r2e2_owned_fast:bool=false` requires the existing genuine LAB Controller exclusive R3.2.2 token and generation; otherwise fails before spawning, `R2E2_REQUIRES_CONTROLLER_LEASE`. Frozen for whole pending task; attempts to switch mode mid-generation rejected. Default stays OFF, and no Earth/WORLD_COMPAT API can activate. Unsupported direct writes into `Controller._runtime` while a lease exists remain outside the lease contract just as in R3.2.2; not advertised as malicious native-code isolation.
- `Controller.run_staged_frame(... use_r2e2_owned_fast=false)` only opts in when LAB/OffMain/R3 are all true; StagedSession forwards the flag. Existing Live Workbench **never opts in**, and accepted R1 GUI path is unchanged. Any PAUSE/restore/cancel revokes the existing Controller source lease. Final adopted state anchored by exact source hash, options, tick and Controller generation.
- Inner worker still executes FULL original source+candidate `Runtime.validate` at final gate, and untrusted direct callers retain FULL final main-thread validation. `E2` adds a one-time complete worker-source admission, so the optimized mode can be slower at small n; inspect native 256 balanced performance rather than assuming a gain.

## Mandatory checks

- True LAB Controller with canonical source fixture injected before source-lease issuance, n4/32/96/256, fresh process. Both legacy strict and E2 owned fast must exactly match ORIGINAL `Runtime.step_spatial_parallel_advance` full serialized state hash and A8 checkpoint, sole global A4 field/grants/ledger and no partial output. Full worker source+candidate validate evidence, joined task exactly once.
- Negative: untrusted `OffMain.advance(... r2e2_owned_fast=true)` without genuine Controller lease must reject before spawning; invalid Controller mode must reject; altering fast policy during active generation must fail; stale source mutation or cancellation/restore must not publish a new canonical tick. Independent verifier must test these with real GDScript hostile aliases.
- Native Windows pinned 4.7.1 Double SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`; Portable official 4.7.1; Linux Double optional. Whole worker wall per population, one-run old-vs-owned speedup is NOT a native SLA. Subsequent balanced repeated 256 Windows, GUI p99/backlog/RSS and full inherited regressions + independent verifier required before any promotion.
- Hard target n256 under one second per canonical tick remains UNMET until repeated native evidence; do not skip canonical backlog/due ticks, alter biology, remove A4 original comparison or weaken direct/public callers to fake throughput.

**VERDICT: OPT-IN EXPERIMENT / CI_PENDING / DEFAULT OFF / NO WORLD ACTIVATION / READY_FOR_MERGE=false.**
