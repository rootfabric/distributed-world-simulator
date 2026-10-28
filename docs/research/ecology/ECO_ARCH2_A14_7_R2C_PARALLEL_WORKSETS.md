# ECO ARCH2 A14.7 R2 Stage C — Detached A13 threaded worksets inside R3 staged global A4

**STATUS:** DRAFT EXPERIMENTAL / performance gain unproven / NO MERGE.

## Provenance

Frozen parent [R2B PR #827](https://github.com/rootfabric/distributed-world-simulator/pull/827) `fc59102bedffc4ef4c5d874579660a4edf09e21e`, TREE `9911a7d70cc0918e0d27a0d165fea5593671adf1`. Earlier R2A #826, R1 #824, R3.2.3 #821. Accepted main `aac301b9a9a89e027f6d99864437eb750a4202ca` untouched.

## Native problem and R2A/R2B discovery

[Windows native R1 #824](https://github.com/rootfabric/distributed-world-simulator/pull/824#issuecomment-6357620300): RTX 4060 GPU p99 6.3ms (excellent) but canonical 256 tick ~17.6 sec with ever-growing tick debt. Stage A portable profile: PREPARE 15.37%, global A4 24.98%, ADVANCE 32.78%, cursor encode 7.38%, source validation 2.62%, candidate validation 2.95%, projection 2.36%. Stage B opt-in 16-workset quota cuts one-run Portable 256 worker 33.14→23.84sec (1.39×) and keeps exact canonical A8; native Windows remains pending.

Stage C attempts another explicitly OPT-IN CPU experiment based on the **already accepted A13 parallel per-workset worker functions**, without introducing per-tile authority. The full original A4 staged allocator remains one synchronized canonical barrier, and all A4 R2 reference-exact checks remain mandatory. The current optimization must not affect original R3.2.3 callers.

## Stage C implementation

- In `resource_lifecycle_runtime_v1.gd::staged_resume`, append optional `r2c_parallel_workers: int=1`, bound 1..8. Only for experimental R3 allocator mode and >1 prepared/advanced workset:
  * PREPARE uses existing `_prepare_units_parallel` from A13, which spawns bounded detached per-unit threads; sample/demand merging is strictly original workset-index order.
  * ADVANCE uses a new staged fragment adapter built with the same accepted A13 pattern: detached worker copies and `_advance_unit_worker`, each Thread joined in a complete wave before **stable workset-index** `_consume_advance_outcomes` into the **existing partial** next_population / propagule arrays. Exact global MAX_PROPAGULES_PER_STEP and first-failure precedence are preserved, not reset per parallel slice.
  * The global ALLOCATE stage is untouched. No speculative grant publication or canonical tick progression before the FULL final receipt.
- `Runtime.resume_staged_global_tick` only passes the trailing research bound to lifecycle; return host-only (noncanonical) actual nested worker telemetry. `OffMain.advance` trailing `r2c_parallel_workset_workers: int=1` uses that bound within the existing single CPU job, frozen per source generation. Attempt to change it before task completion returns `R2C_WORKER_BOUND_CHANGED`. Retains all R3.2.2 trusted Controller lease checks and full source/candidate validation, direct-service strict source validation.
- A13's workset order, member iteration, random seed stream and entire biological formula remain unchanged. No new data is persisted in Runtime, cursor or checkpoint. R2C counters live in transient per-worker profiling receipts only. Default = 1 everywhere, including existing Controller/Workbench/real Earth paths; NO production opt-in.
- The test-only n4/32/96/256 paired profile runs **16 worksets/resume with 1 nested worker** versus **16 with 4 nested threads**, fresh Godot processes. The immutable source and original A13 full parallel reference must produce **byte-exact canonical Runtime, approved frozen first-tick hash, byte-exact A8 checkpoint** on BOTH paths. Must prove actual `r2c_peak_workers>=2` and nonzero threaded worksets for n>=32, exactly one global A4, stage counts unchanged, no partial grants, one join, full source and candidate receipt, no thread leak. Falsify bound 0/9 and mid-flight changed bound.

## Acceptance

1. Source HEAD/TREE pinned and clean; Portable Godot 4.7.1 original exact 4/32/96/256 fresh processes plus tamper/negative fences; inherited R3.2.3/R2B regression.
2. Independently reproduced Windows Godot 4.7.1 Double SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, 4/32/96/256 fresh paired evidence and native exit; Linux Double if runner available.
3. Repeat n256 native independent samples (both orders, interleaved) for credible median/variability rather than claiming one-run speedup. Independent separate verifier must test source tamper after worker completion, PAUSE/restore/reap and concurrent workset failure precedence. No merge without review.
4. Optimizing throughput to **<1s/tick** remains a target only. GPU Windows p99 and sustained debt/RSS evidence are separate full GUI gates; do not infer these from portable headless comparisons. If nested threads increase wall/RSS or nondeterminism on Windows, reject R2C and retain frozen R2B.

**VERDICT = EXPERIMENTAL / CANONICAL_EXACT_UNVERIFIED_UNTIL_CI / GPU_NOT_RETESTED / NO MERGE.**
