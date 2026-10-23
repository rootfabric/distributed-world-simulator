# ECO ARCH2 A14.7 R2 Stage B — Paired Batched Worksets Experiment

Experimental performance candidate, DEFAULT 1 workset/call unchanged; not accepted into main or R2 Stage A without exact and independent reviewer.

Parent: R2 Stage A PR #826, frozen HEAD `94eb7fa39f5901771d1aa0186172d23e46785084`, TREE `d3ab002013473dfc67bd600db9a2dcc725f8631d`, itself direct child of R1 PR #824. Main still `aac301b9a9a89e027f6d99864437eb750a4202ca`.

## Profiling evidence motivating this narrow experiment

R2 Stage A [Portable Exact #39904239760](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39904239760) **PASS all 4 scale hashes/A8**. n256 worker 20.195s, shares: ADVANCE 32.78%, global A4 (BEGIN+RESUME) 24.98%, PREPARE 15.37%, redundant pre-resume `C.encode(cursor)` 7.38%; per-worker final source validation 2.62%, final candidate validation 2.95%, projection 2.36%. Staging calls `Runtime.resume_staged_global_tick(..., max_worksets_per_call=1)` even though Runtime and Lifecycle already explicitly support bounded multiple worksets per call. Grouping worksets in one call may avoid repeated full source validation/checksum/deep cursor cloning and reduce CPU time without altering the canonical reduction order. Native Windows attribution still pending; exploratory portable cost is not cross-host SLA.

## Change

- Only new optional **trailing host OffMain parameter** `worksets_per_resume: int=1` allowed range 1..64. Pass it through existing `Runtime.resume_staged_global_tick` (already supports this quota). The serial order of organism processing and a single global A4 allocation remains exactly as before. R3.2.3 Controller/Workbench usage does not pass this new parameter and retains default 1; WORLD_COMPAT/Earth/default-off unchanged.
- Never change quota while a task is pending; fail-closed `R2B_WORKSET_BATCH_CHANGED`. No new fork of A4 or biology, no parallel writes, no skipping the original staged R2 canonical byte-for-byte allocator proof or any full Runtime.validate.
- Paired direct OffMain CPU profiling compares quota 1 to quota 16 using the SAME detached source/options, then to the accepted full A13 parallel-advance reference, original frozen canonical hash and serialized A8 checkpoint. The direct API is intentionally UNTRUSTED: both paths still perform full main-thread source admission after the worker; measure worker.wall for speed comparison, not host frame wall.
- Separate Godot fresh processes per population 4,32,96,256; negative tests reject zero, >64 and mid-generation changed quota. Finish complete task and exactly-once join/reap.
- No throughput acceptance on portable alone. Need native Windows exact to report gain; if speedup small, do not widen scope into generic parallelization until an independent profile confirms work.
- Target <1s at 256 remains future, not claimed by workset batching experiment. Mainline 256 GUI p99 and backlog were already separately measured in R1.

**Verdict: EXPERIMENTAL / NO NATIVE PERF ACCEPTANCE / NO MERGE**.
