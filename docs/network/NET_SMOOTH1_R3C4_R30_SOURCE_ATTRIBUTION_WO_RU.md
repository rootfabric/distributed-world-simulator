# NET-SMOOTH1 R3C.4 R3.0 — Source Attribution, immutable-boundary baseline

## Decision / scope

R2 #787 pinned HEAD `f64fed2430f1292773d1561f881e5c8a4cc89075`,
TREE `01731ee75418c58c2f2d2e16fb39d29b9a167def` is
`FUNCTIONAL_PASS / PERF_FAIL / NO_MERGE` after 21 October independent
GUI evidence. R3 conditional Issue #792 is triggered.

**R3.0 is measurement only**, not the requested immutable projection R3.1.
M6 generation, disk format, checksum, ACK escrow, single writer, pending command
order, replay idempotence and legacy default OFF remain unchanged. No merge
without separate exact source/native/GUI evidence, independent review and Project
Control owner rotation.

## Critical source diagnosis before optimization

In `m3_dedicated_server_runtime_p2.gd::_submit_async_movement_checkpoint`,
`replay_ms` is time from *before* `M6ReplayOutbox.to_dict()` until its
return. The call to `submit_frozen_gameplay_source()`, including two
`duplicate(true)` operations, occurs **after** `after_replay` and contributes
to `handoff_ms`. A performance report referring to `replay_ms` as
writer deep-copy time has misattributed the stage.

The outbox `to_dict()` itself calls `_service.export_replay_state()` (which
traverses the entire service operation ledger and exports ownership/item replay)
and `Utils.finalize_json_checksum()` (which canonicalizes/detaches the
aggregate). The durable gameplay state exporter separately traverses players,
ownership, item graph and resource mining. Caching/reducing any of these requires
coherent authority/revision/operation fences, not a shallow alias into worker.

## Changes

1. New server-only opt-in env/CLI canary
   `DWS_NET_R3C4_R30_STAGE_ATTRIBUTION=1` /
   `--r3c4r30-stage-attribution`. Requires R1 and R2 (fails closed without R2);
   without the flag existing R2 path executes unmodified.
2. A pure separate `M6ReplayOutbox.to_dict_profiled()` returns the exact
   unchanged checksum/outbox layout plus nested durations
   `gameplay_export_ms` and `checksum_detach_ms`. The normative `to_dict()`
   is *unchanged*. Native parity test requires exact dictionary and checkpoint
   bytes, including a caller-alias mutation attempt.
3. Writer `submit_frozen_gameplay_source(..., profile_handoff_copy=false)`
   still does synchronous `duplicate(true)` twice **before** semaphore post.
   The opt-in return carries `handoff_copy_ms`; no zero-copy or worker-side
   reading of live state has been attempted.
4. `checkpoint_capture` trace gains the diagnostic opt-in keys:
   `r30_replay_gameplay_ms`, `r30_replay_checksum_ms`,
   `r30_writer_deep_copy_ms`, `r30_replay_ledger_count`,
   `r30_outbox_count`. Preexisting `authority_ms`, `replay_ms`,
   `handoff_ms`, `capture_ms` remain comparable.
5. Read-only diagnostic reducer
   `tools/net_smooth1/analyze_r3c4_r30_capture_stages.py` emits
   per-stage p50/p95/p99/max, sizes and unattributed outer replay overhead,
   while preserving the separate **unmodified** normative analyzer.
6. Negative Python/source tests and real GDScript M6 disk parity/regression
   test, pinned native Windows/Linux Exact CI.

## Independent Windows work order

Do **not** use the divergent R2 #790, do not merge #787 or this branch. Fresh
fetch, clean detached commit of this R3.0 branch, retain exact TREE and source
identity. Use a single Godot binary for 3 matched 120s 2-client
Earth+Quaternius R31 GUI pairs. Prefer canonical pinned SHA256
`3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`.
An alternate SHA `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`
is a separate **non-identical environment class** even if its version string
matches; preserve provenance and never label such runs pinned Exact.

Common arguments to the established harness `run_net_smooth1.py`:
`--godot <console-exe> --mode gui --scenario r31-reconnect-roundtrip --duration 120 --warmup 20 --profile LOCAL --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope`.

Run 3 paired **R3.0 OFF** vs **R3.0 ON** on the same R3.0 HEAD;
the only additional switch in the ON arm is
`--r3c4r30-stage-attribution`. Keep report/manifest/raw trace from every
process, exact Quaternius provider and asset manifest, process SHA, stage
breakdown, independent source/native hashes. Use unique OutputRoot each run.

For each ON run after normative analysis:
`python tools/net_smooth1/analyze_r3c4_r30_capture_stages.py <OutputRoot>/server/trace.jsonl --output <OutputRoot>/r30_stages.json`.

Compare median/worst across 3 repetitions, checkpoint count vs outbox/ledger
size, R2 OFF vs R3.0 ON diagnostic observer overhead, p99/p999/max/59Hz,
Quaternius, M6, checksum/disk and replay. R3.0 must not materially worsen
p99; no acceptance without full GUI and cold/native exact.

## Slow ITEM remains separate

The 21 October evidence reported 3× `INCONCLUSIVE` due
`P1A_WAIT_PRIOR_PERIODIC`. This is **not** a correctness PASS and is not
evidence that M6 violates durable-before-ACK. The test-only diagnostic
repair uses a separate branch `repair/net-smooth1-slow-item-periodic-admission-r1`:
opt-in retry of exactly the same operation_id and payload on the explicit
transient code, with deadline and negative falsifiers; never convert refusal
into ACK. Compare canonical original test result and repaired diagnostic
without changing authoritative server semantics.

## R3.1 gate

Only after R3.0 quantifies replay gameplay-export vs checksum-detach vs writer
deep copy on real runs may we implement and justify a versioned immutable
projection or any ownership-transfer optimization. Strict revision/epoch and
M6 replay high-watermark fences and no mutable Node/Resource aliases required.
Target *hypothesis*, not proof: periodic `checkpoint_capture` p99 <=5ms while
all frame and durability standards continue to pass. SEAM-E2E and Project
Control remain independent blocking gates.
