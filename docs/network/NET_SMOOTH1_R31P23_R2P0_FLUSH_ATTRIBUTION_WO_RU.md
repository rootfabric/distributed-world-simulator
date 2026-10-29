# NET-SMOOTH1 — P2.3 R2.0 TRANSPORT FLUSH ATTRIBUTION / Windows Work Order

## Why this branch exists

Parent is the independently tested P2.3 R0 [Draft #823](https://github.com/rootfabric/distributed-world-simulator/pull/823), product HEAD `cdb48e605487951c0e9a38ddffa92d4c4b946c8b`, TREE `57a480b26db8bf042b956e1229a97d9d2502944f`. This R2.0 branch is intentionally a **sibling of P2.3 R1 Draft #825**, NOT its descendant. Do not silently inherit R1 deferred stdout logging, which improved debug_event duration but worsened server p99. B3 Windows Job Guard [Draft #820](https://github.com/rootfabric/distributed-world-simulator/pull/820), TOOLING_HEAD `b4cbf565764cea16eb81cc163824b2a237e2cb8a`, remains EXTERNAL in a separate tooling worktree. No merge/force/main changes.

P2.3 R1 #825 independent Windows verified HEAD `9d6f00feb4c846d9e9a299efbb0f2b9a84477000`: native/source PASS; two 60s real Earth+Quaternius GUI OFF/ON on SAME HEAD were server p99 27.285/28.372ms, p999 35.664/65.779ms, max 40.883/98.950ms, clients A failed p99. Debug-event p50 fell 2.931→0.024ms; 50 FIFO entries printed with no loss and no overflow; **entire p99 was WORSE**, so do not merge R1 as perf fix. Outbound COMPACT flush on the two runs: 5414.7/5530.7ms total, p99 3.28/5.19ms and max up to 44.46ms. Old P2.2/P2.3 tail attribution: outbound_flush > frame_create > boundary_send >> payload clone. No authority to preencode future tick or migrate mutable sessions/ENet into worker.

The underlying source was inspected: NetworkTransportBoundaryV2.flush_outbound duplicates frame before sending; a NetworkConditionSimulatorPort wrapper **revalidates** the frame and computes canonical JSON size even on LOCAL passthrough; delegate ENetMultiPeerTransportPort then validates and encodes ProtocolFrameV2 again and calls ENet put_packet + peer stats. Repeated validation/canonicalization is a plausible CPU candidate but **NOT a measured root cause** until this exact R2.0 profile.

## Implemented P2.3 R2.0 — strictly opt-in measurements

Server-only `DWS_NET_R31P23R2_FLUSH_ATTRIBUTION=1` / `--r31p23r2-flush-attribution`, default OFF; requires existing `--r31p22-loop-attribution` and inherited persistent M6/USER1/R31a/P0/P1/R2 stack. Invalid mode/missing dependency fails closed.

Only COMPACT_GAMEPLAY_SNAPSHOT packets are instrumented. Boundary `r31p23r2_flush_packet` is emitted with exact server-local `Engine.get_process_frames()`, original frame_id, session sequence, delivery mode, queue preparation time, detached frame duplicate time, actual port call duration, success/error. The same original `_port.send_to_peer()`, `session.reserve_queue()`, `commit_outgoing_sequence()`, `queue pop`, `release_queue()` and `flush_outbound(32)` are retained.

Condition simulator reports `frame_validate_ms`, `canonical_json_ms`, predelegate and delegate total, plus explicit passthrough Boolean; real ENet delegate reports `validate_ms`, `frame_encode_ms`, channel setup, `put_packet_ms`, and peer stats, with exact totals. All telemetry is in server local trace/return details when canary ON, **not on the wire**, not new gameplay authority, not an ACK or M6 field. On default OFF the original packet bytes/checksum/order and M6 writer are unchanged.

Strict read-only `tools/net_smooth1/analyze_r31p23r2_flush_layers.py` uses the accepted P2.2 analyzer: complete trace/footer/zero dropped records and EXACT server engine-frame matching to all original COMPACT outbound_flush events; missing/duplicate frame identities, send failure, invalid channel/mode, impossible additive stage sums or incomplete coverage all fail INCONCLUSIVE. Reports complete per-peer p50/p95/p99/max and top worst COMPACT frames with boundary/simulator/ENet substage sums. It preserves original report.json verdict and does not reclassify an uncovered frame gap as OS/limiter. Note ENet `put_packet_ms` is API call time, **not actual network delivery latency**.

Native `test_net_smooth1_r31p23r2_flush_attribution.gd` verifies exact default-OFF three layers, invalid mode and dependency gates, and real server configuration propagates to ConditionSimulatorPort and ENet delegate. Python source contracts ensure one original create/send/flush, FrameScript canonical checksum validation, unchanged P1/M6, no worker/tick changes. Synthetic strict reducer falsifier covers 100 complete packets, optional simulated condition path, lost packet, duplicate frame ID, wrong mode, failed send, impossible simulator/ENet sums.

## G0 — native and identity first on DESKTOP-QNAGSTI

- Fetch exact R2.0 PR head after publication and work in a fresh clean detached PRODUCT worktree. Keep original #825, #823 and main unchanged. Real Godot 4.7.1.double editor + double export binaries; wrapper pinned SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a62507a8a7a5`; separately hash/main compare observed `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`. Real original Quaternius CC0 224 assets, no fallback.
- Cold import; exact Windows/Linux CI and local Python `test_net_smooth1_r31p23r2_source_contracts.py`, `test_net_smooth1_r31p23r2_flush_layers.py` plus P23/P22/P1 inherited suites. Native new `test_net_smooth1_r31p23r2_flush_attribution.gd` and inherited M6 durable-before-ACK/replay, USER1/CHAR2.
- If any source/native/parse failure, mark FAIL, repair only on a new HEAD with new exact evidence. No GUI PASS claims.

## G1 — FIRST one short 60s real GUI ON, not a six-run matrix

External #820 Job Guard from independent TOOLING worktree, one canonical 2-client Earth+Quaternius GUI (OpenGL3 900×600, VSync OFF, 60fps, LOCAL, scenario r31-reconnect-roundtrip), warmup10 + measured60s, unique evidence root. Use the same common R3C / P1 / P2.2 flags as #823:

```text
--mode gui
--scenario r31-reconnect-roundtrip
--warmup 10
--duration 60
--profile LOCAL
--r3c-async-admission
--r3c2-avatar-prewarm
--r3c2-server-phased
--r3c3-staged-earth
--r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing
--r3c4r2-worker-envelope
--r3c4r31-replay-projection
--r3c4r31b-durable-attribution
--r31bp1-durable-chunks
--r31p22-loop-attribution
--r31p23r2-flush-attribution
```

Do not include `--r31p23r1-defer-checkpoint-debug` or `--r31p23-completion-attribution` unless a separate controlled diagnostic requires them. Product lineage is #823, not #825.

After run, do not alter raw evidence; run unchanged normative analyzer and the strict R2.0 source attribution:

```powershell
python tools/net_smooth1/analyze_r31p23r2_flush_layers.py "<ON_RUN_ROOT>" --output "<ON_RUN_ROOT>\r31p23r2_flush_layers.json"
```

Require all per-frame COMPACT events accounted, exact old P22 frame join, zero failed/unknown sending, all 3 `measure.end.ack` and #820 `job_receipt.json` natural_exit, after.active0/pids[], forced false. Preserve original FAIL/exit/first JOIN flake. If P23R2 tool sees nonpassthrough network condition traffic, report this separate population explicitly; do not pretend an ENet call was made for queued packets. Preserve all server/client p99/p999/max and server simulation >=59Hz; do not skip >100ms frames.

G2 only AFTER a good complete ON and healthy host/clients: one same-HEAD **short OFF** without `--r31p23r2-flush-attribution`, otherwise identical, to isolate instrumentation overhead. Previous #825 OFF/ON on a different HEAD are not an exact comparator to R2.0. Do NOT run 3×120s until a concrete profitable R2.1 implementation exists.

## R2.1 candidate decision and release gate

1. If `simulator.canonical_json_ms` or redundant `FrameScript.validate` dominates, the first R2.1 would attempt a single-pass canonical immutable packet cache or limited proven-redundant validation elimination, preserving exact payload checksum, malformed-input rejection, per-peer session/sequence/delivery, packet-size guards, and all negative tamper tests. NO blind validation waiver. Source immutable bytes must be detached after current authority snapshot, not future tick.
2. If `enet.frame_encode_ms` dominates, independently isolate canonical frame validation vs serialization/UTF8 and consider immutable detached byte envelope for CURRENT frame with byte-perfect checksum verification, not networking in worker.
3. If `enet.put_packet_ms` dominates, investigate ENet on-main API and per-peer bounded scheduling with unchanged transport session sequence, READY/CONTROL/RESYNC priorities, coalescing and backpressure. Do not silently defer committed command ACK.
4. If `boundary.detached_frame_copy_ms` dominates, explore removing only a demonstrably redundant clone with caller-poison, replay/tamper, and queue ownership falsifiers.
5. If no nested component explains COMPACT flush, new instrumentation for `flush_outbound` queue scanning/telemetry is required before assuming OS/GPU stall. No magic frame cap changes.

To claim release: immutable R2.1 fix HEAD; three matched full 120s two-client Earth GUI pairs, all server/client p99<=25ms, p999<=50ms, max<=100ms, sim>=59Hz, zero M6/ACK/checksum/USER1/seam violations and no unexplained >100ms frames, three 1800ms slow ITEM cases, kill/restart, two-player A→B→A, full exact Windows/Linux native, Project Control main registry, P7.4 phase harness, independent SEAM-E2E and unresolved first JOIN checksum issue #815. Any retry/failure must be reported. NO_MERGE; READY_FOR_MERGE=false.
