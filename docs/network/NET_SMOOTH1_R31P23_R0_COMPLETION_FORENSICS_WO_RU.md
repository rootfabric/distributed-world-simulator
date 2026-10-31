# NET-SMOOTH1 R31 P2.3 R0 — completion and COMPACT forensic Work Order

## Frozen identity and motivation

Parent Draft PR #822, exact HEAD dc7ba78a430d663c4e5efd5d6a59c29425aeb16f; #814 HEAD fdfbfb3b8dff911e6fd081a157652a28e1052cff ancestor. Job Guard PR #820, TOOLING_HEAD b4cbf565764cea16eb81cc163824b2a237e2cb8a is an EXTERNAL verifier. No main/product merge or force-push.

Independent Windows P2.2 on #822 exact HEAD: 60s ON Earth+Quaternius 2 clients, 3612/3612 exact joined frames, server p99 25.143ms vs <=25 norm FAIL, max 54.764ms, client p99 about 22.5ms PASS, functional PASS and B3 clean. Among 39 frames >25ms: snapshot publication dominant 18, movement persistence 9, movement completion 8, boundary poll 4. Worst movement_persistence frame #2867 was 25.11ms with 27.02ms uncovered probe time (NOT proven host/OS/limiter). COMPACT totals ~2.6ms p50 per peer over 2408 events. The user summary did NOT say whether per-peer frame_create, send, flush or payload clone dominates within the actual slow frames. Prior same-HEAD P2.2 OFF failed both client connections -> INCONCLUSIVE, not a usable observer-overhead baseline.

## Safety decision

Do NOT preencode a future authority tick on worker: the next tick's world snapshot has not yet been captured. NetworkTransportBoundaryV2.create_frame_for_peer also derives per-peer session ID, outgoing sequence and server global frame ID from mutable live sessions; ProtocolFrameV2.create hashes canonical payload and validates exact wire schema. Any later worker computation needs detached authoritative current-tick DTO with strict version/epoch/tick/ITEM/seam fence before publish; peer sequence and transport must stay on main thread. Never put a live Node/ENet/session into a worker. Worker implementation requires its own isolated future PR and deterministic wire/checksum parity on malformed and valid cases; NOT authorized by total compact_send time alone.

AsyncCheckpointWriter.poll_completed() is a nonblocking metadata acquisition, not disk-thread join. A 25ms completion-related frame might be metadata clone, generation/ACK gate, debug event or synchronous diagnostic write. Instrument actual work before altering ACK, writer or scheduling.

## This PR: diagnostics only, default OFF

Server-only flag DWS_NET_R31P23_COMPLETION_ATTRIBUTION=1 / --r31p23-completion-attribution requires P2.2 --r31p22-loop-attribution and its full P1/P0/R31a/R2 persistent USER1 stack. Invalid/missing mode fails closed. No M6 replay/checksum/disk/ACK semantics, no COMPACT payload sequence, no gameplay validation, no FPS cap change.

For each actual finished async movement generation, r31p23_movement_completion records SAME engine_frame, generation and non-overlapping times:
- poll_completed_ms
- generation_ack_gate_ms
- metadata_copy_ms
- completion_trace_ms
- telemetry_ms, debug_event_ms
- diagnostic_report_ms, diagnostic_report_deferred
- total_ms

Read-only tools/net_smooth1/analyze_r31p22_loop_stages.py retains original normative FAIL and adds per-frame compact_wire_sums_ms (clone, frame-create, boundary-send, outbound-flush), per-frame movement_completion_stages_ms, and aggregate completion component p50/p95/p99/max. Lossy traces, mismatched frame IDs, impossible stage sums, a COMPACT send failure or missing required completion all fail closed. --require-completion requires at least one measured real writer completion; leave it OFF for historical P2.2 traces.

## Windows execution A — NO new GUI, old P2.2 evidence

Fresh detached P2.3 R0 checkout at PR exact HEAD/TREE. Identify original P2.2 ON run root under C:\EVIDENCE\P22R1-20261023-113606\attempt2; choose directory actually containing manifest.json/report.json/server/trace.jsonl.

From new P2.3 worktree run:

python tools/net_smooth1/analyze_r31p22_loop_stages.py "<ACTUAL_P22_ON_ROOT>" --output "C:\EVIDENCE\P23-old-P22-stage-reanalysis.json"

Do not pass --require-completion on old P2.2. Keep original JSONL byte-for-byte and report raw SHA256 before/after. Report the EXACT same-frame sum of frame_create vs boundary_send vs outbound_flush vs clone in 39 actual >25ms server frames and top100 worst frames; separate per-peer event p50/p99 from per-frame sums; no independent p99 addition. If frame_create is not dominant, do NOT implement a speculative frame-preencoding worker. Note historical OFF connection failure remains INCONCLUSIVE.

## Windows execution B — only one short 60s new GUI P2.3 ON, plus optional OFF

After source tests (test_net_smooth1_r31p23_completion_source.py, inherited P2.2 Python and native test_net_smooth1_r31p23_completion_attribution.gd, inherited M6/USER1), cold import, verify exact Godot double 4.7.1 wrapper SHA 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5 and separately record main Godot exe SHA 6464da35..., real CC0 Quaternius 224 files no fallback.

Separate #820 Job Guard TOOLS worktree; run real Earth two-client OpenGL3 900x600 VSync off 60fps cap, LOCAL scenario r31-reconnect-roundtrip, 60 seconds measure, 10 seconds warmup. Both legacy R31a/P0/P1 and R31P22 flags ON, plus new --r31p23-completion-attribution ONLY on this run. Use existing canonical args:
--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope --r3c4r31-replay-projection --r3c4r31b-durable-attribution --r31bp1-durable-chunks --r31p22-loop-attribution --r31p23-completion-attribution.

Analyze without changing raw trace:

python tools/net_smooth1/analyze_r31p22_loop_stages.py "<NEW_P23_ON_RUN_ROOT>" --require-completion --output "<NEW_P23_ON_RUN_ROOT>\p23_completion_stages.json"

Correlate same-frame movement_completion_ms vs poll_completed, generation/ACK, metadata, trace, debug and diagnostic report; preserve all original runner PERF_FAILs and raw frame >100ms. No hidden exclusions. Verify all 3 measure.end.ack, Job receipt natural_exit/active0/pids empty/forced false, no foreign Godot killed, native M6/ACK/replay safe. If zero completion events -> INCONCLUSIVE; do not fake metrics.

One optional same-new-HEAD short OFF run without P2.3 diagnostic only AFTER a complete ON run with healthy 2-client connections and manageable host load. Do not count earlier OFF INCONCLUSIVE as perf baseline. No 3 pairs x120s at diagnostics stage.

## Real P2.3 implementation gating

- Only if exact per-frame frame_create dominates compact tail: separate worker prototype on DETACHED current-tick immutable DTO, no future-tick guessing, bounded queue, strict source epoch/tick/authority/ITEM and per-peer session sequence fences and bit-exact canonical wire/checksum/negative parity before sending. No live Godot/ENet on worker.
- If outbound_flush dominates: examine peer ENet queue/canonical coalescing, preserve sequence/reliability and RESYNC ordering.
- If completion gate/debug/report dominates: repair only costly proven substep; ACK still waits for durable commit and generation monotonic, shutdown barrier unchanged.
- If uncovered remains dominant: independent engine-cadence study, not assumption of OS sleep.

Product acceptance remains server/clients p99 <=25ms, p99.9<=50ms, max<=100ms, sim >=59Hz, zero M6/replay/ACK/authority/checksum violations, real 3 x 120s paired GUI on later REPAIR HEAD, native Windows/Linux, 3 slow ITEM, crash-kill/restart, seam A-B-A, Project Control/P7.4/SEAM-E2E, issue #815 first JOIN checksum flake. This R0 is diagnostic only.

READY_FOR_MERGE=false. NO_MERGE / NO_FORCE / NO_MAIN_CHANGES.
