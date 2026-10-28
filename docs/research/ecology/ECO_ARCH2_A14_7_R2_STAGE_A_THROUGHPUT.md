# ECO ARCH2 A14.7 R2 — CPU simulation throughput / Stage A Profiling

STATUS: DRAFT, UNDER TEST, not a throughput fix, not merge-ready.

Frozen direct parent: A14.7 R1 PR #824 at `e04e0a14a5c46e82ab9c3d2aad7cf0bf3a2bc9f0`, TREE `bd3470cc7bc478afe432638476891756821dd2d7`. Main frozen at `aac301b9a9a89e027f6d99864437eb750a4202ca`. Never touch R1, R3.2.3, main or the original R1 independent verifier repair.

## Grounded native Windows evidence

[Windows R1 receipt](https://github.com/rootfabric/distributed-world-simulator/pull/824#issuecomment-6357620300), exact pinned Windows Godot Double, i9-13900H / NVIDIA RTX 4060 (driver 610.88), real native session: 4/32/96/256 pass functional and canonical 23/23, GUI p99 6.3–6.5ms (run 2 at 256 7.312ms), 256 zero >50ms, canonical state/A8 parity. CPU global ecology tick at N=256 ~17.6 seconds, Worker 2 ticks ~35.3s, MAX backlog 65, final 64. Memory within run bounded; no observed process leak. Independent verifier had a test-only initial tick-0 synchronous event counting defect, RED→GREEN correction separately published at `fix/a147-fresh-verifier-single-snapshot-event`, HEAD `62c1bf7cf...`.

**Consequence:** GPU is NOT the limiting subsystem; R2 starts with exact CPU hot path attribution. A sub-second 256 tick requires ~17.6× CPU wall reduction and is a TARGET, not achieved. Capping UI debt without reducing CPU wall DOES NOT drain owed canonical ticks; do not hide backlog, skip authoritative ticks or advance the canonical clock speculatively.

## Stage A — instrumentation (implemented now)

Versioned worker-private measurement added only to `scripts/ecology/workbench/off_main_r3_session_v1.gd`. No change to A5/A4/A6, C.encode, stage quota, Runtime validation, worker ownership, canonical state or A8 bytes. For each complete task, measure:
- Exact host worker begin, time spent `C.encode(cursor)` and peak serialized cursor bytes.
- Sum/count of `Runtime.resume_staged_global_tick` calls by source lifecycle phase PREPARE / ALLOCATE Begin / ALLOCATE Resume / ADVANCE, and finalizing ADVANCE resume subset.
- CPU worker final full source+candidate validation, worker snapshot projection, whole wall, unattributed wall.
- Summary is emitted only after existing safety receipt and accepted tick (status/profile JSON). No timestamps or counters enter state, cursor checksum or checkpoint. Direct-service untrusted source admission retained.

Product Scale test `validation/ecology/evo_arch2_a14_7/test_a147_r2_phase_profile.gd` uses the EXACT accepted 4/32/96/256 deterministic canonical fixture and real LAB Controller with source injected BEFORE lease. Serial A13 `Runtime.step_spatial_parallel_advance` is the independent reference. Every case must prove full Runtime encoded bytes, accepted first-tick hash, A8 checkpoint exact, no source mutation, one global A4 call, one joined worker, no speculative grants, and internally consistent phase counters. Each population is a separate Godot process.

## Gates

Portable Godot 4.7.1 Stage A must PASS all sizes before optimization proposal; Windows 4.7.1 pinned Double must reproduce and give percentage table of PREPARE, ALLOCATE, ADVANCE, per-resume source validation/checksum and final full validation+snapshot; Linux Double independent comparison when runner available. Preserve exact branches and tests.

The phase count `finalize_us` is included in `advance_us` and MUST NOT be added to the sum of the three phase buckets. Full nested A4 R2 cursor validation is intentionally retained in Stage A.

Acceptance classification:
- `SOURCE_PROFILE_PASS` if exact gates+phase receipts on portable.
- `WINDOWS_PROFILE_PASS` only after exact pin/native confirmed and full 256 phase data, not on headless portable.
- `SIM_THROUGHPUT_PASS` only if genuine 256 full global tick wall <1000ms on pinned Windows across repeated runs, canonical bit equality, 10m native workload debt <=4, RSS growth <20MB and independent verifier. None are claimed by Stage A.

## R2 Stage B (conditional on actual measured fractions)

- If PREPARE or ADVANCE is dominant: use existing A13 verified unit worker methods with detached inputs and stable workset-index reduction into the **single global A4** barrier. No unchecked shared-array writes.
- If ALLOCATE/R2 resume dominant: first profile `StagedA4R2.begin/resume` and nested full cursor verify cost; consider trusted opt-in batch size reduction of repeated checksums with independent falsifiers, not bypassing original A4 reference or skipping full validation.
- If cursor encoding/state checks dominant: profile counts and explore an exclusively-owned immutable worker cursor lease while retaining complete cryptographic-bound source/options/state validation and direct untrusted strict path; never eliminate validation solely based on hash header.
- If O(N²) found: replace scans with precomputed indexed workset lookups only if all output ordering and failure precedence remain exact; preserve evidence from independent mutating-input falsifiers.
- If no plausible <1s target from safe exact optimizations: report the limit honestly and propose native/C++/GDExtension or bulk-data structure redesign as separate gated research, never fake tick progress.
- A14.7 R3 backlog policy is separate: wall-time rate control, metrics/debt honest, never discard canonical ticks.

No merge or production activation. The goal is to identify the actual cost distribution before selecting optimization.
