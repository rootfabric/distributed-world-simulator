# NET-SMOOTH1 R31 P2.3 R1 — bounded deferred periodic checkpoint debug (Windows Work Order)

## Frozen base and measurement that authorizes this narrow repair

Exact product parent: independent P2.3 R0 [Draft PR #823](https://github.com/rootfabric/distributed-world-simulator/pull/823), HEAD `cdb48e605487951c0e9a38ddffa92d4c4b946c8b`, TREE `57a480b26db8bf042b956e1229a97d9d2502944f`. Ancestors: P2.2 #822 `dc7ba78a430d663c4e5efd5d6a59c29425aeb16f`, P2.0 #814 `fdfbfb3b8dff911e6fd081a157652a28e1052cff`. External B3 Job Guard #820 TOOLING_HEAD `b4cbf565764cea16eb81cc163824b2a237e2cb8a` is **not merged** into product; use separate tooling worktree. Do not change any original parent evidence, main or PR heads. All products remain Draft, READY_FOR_MERGE=false.

Independent 23 Oct Windows R0 evidence [#823 comment](https://github.com/rootfabric/distributed-world-simulator/pull/823#issuecomment-6357430570):
- old exact #822 39 frames >25ms: outbound_flush SUM **65.24ms**, frame_create 30.46, boundary_send 26.44, payload_clone .049. Pre-encode future snapshot on worker is **NOT** authorized; frame_create is not dominant.
- R0 real new P2.3 ON (60s) original PERF_FAIL, server p99 **26.684ms**, OFF same HEAD p99 **25.189ms**, clients both PASS; OFF/ON difference ~1.5ms reflects the *entire P2.3 instrumentation + workload*, not proven R1 benefit.
- 39 actual movement completion events, expensive synchronous original `_debug_event("MOVEMENT_CHECKPOINT_COMMITTED")` p50 **2.56ms**, max11.07ms, sum134ms over slow completion frames; ACK gate, worker polling and metadata copy negligible. `_debug_event()` JSON.stringify + `print()` synchronous main-thread logging. This is a concrete, measured candidate, but NOT the only source of p99-tail.
- new raw 89 frames >25ms: COMPACT outbound_flush SUM **297.5ms**, frame_create131.6, send110.7 and clone .20. Dedicated outbound_flush work will follow in separate R2.1; this PR does not touch ENet.
- first P23 R0 ON attempt was INCONCLUSIVE with dual-client/first-JOIN PAYLOAD_CHECKSUM_MISMATCH, issue #815 still OPEN, cannot be waived by successful retry.

## Implemented opt-in source change (P2.3 R1 only)

Server-only `DWS_NET_R31P23R1_DEFER_CHECKPOINT_DEBUG=1` / `--r31p23r1-defer-checkpoint-debug`, default OFF, requires the P2.3 R0 `--r31p23-completion-attribution` canary (which itself requires full P2.2/P1/P0/R31a/R2 M6/USER1 stack). Invalid env or missing P23 dependency fails closed.

ONLY the **debug stdout line** `MOVEMENT_CHECKPOINT_COMMITTED` for a *successfully completed periodic async checkpoint* is changed when R1 enabled. The generation is **already committed to disk**, `_checkpoint_generation` already advanced, M6 `observe_periodic_commit()` completed and all original telemetry/trace code remains. Every other debug log, ITEM/ACK, resource/ownership, JOIN/LEAVE, snapshot, compact wire and ENet path is unmodified.

Instead of synchronous `print(JSON.stringify(...))` in that completion frame, create a private immutable JSON text line with the **original main PID, completion event monotonic time_msec, exact M6 generation and async=true**. Append to a bounded FIFO of max **32 lines**. Then print max ONE prior-frame line on a **non-snapshot**, no-ITEM/no-postcommit frame with preexisting measured main-loop work <=**8ms**. This shifts optional diagnostic console overhead without pretending it disappears: original `server_loop.process_ms` includes later print and optional same-frame `r31p23r1_debug_flushed` captures actual `print_ms` and `queue_delay_ms`, joined by engine_frame.

No hidden loss: a full queue falls back to immediate legacy print with explicit `r31p23r1_debug_overflow` and counter; overflow is NOT a clean performance acceptance. On graceful server stop (after current movement writer completion), drain every pending line before final reporter/teardown. No background debug writer, no new gameplay worker, no Node/ENet shared across threads. Debug stdout ordering relative to unrelated SERVER_HEALTH events can change while per-generation FIFO and original event timestamps are preserved; this is intentional diagnostic-stream behavior, NOT wire/M6 ordering.

Native Godot `tests/runtime/test_net_smooth1_r31p23r1_deferred_checkpoint_debug.gd`: full opt-in/server/default-off/mode gates, exact generation+PID+original timestamp JSON and FIFO, no same-frame print, bounded 32-slot saturation with synchronous fallback, shutdown drains all queued entries, M6 generation no rollback. Inherited R31/P23/P22/M6/USER1 tests unchanged.

Python `tests/tools/test_net_smooth1_r31p23r1_deferred_debug_source.py`: verifies source gateway: original completion is M6 durable and ACK-bound before queue, no other code enters queue, default OFF legacy print, one original _boundary create/send/flush each, no new FPS or gameplay source of truth.

Read-only `tools/net_smooth1/validate_r31p23r1_debug_fifo.py` audits entire original trace+console log, validates trace END/no dropped event, and requires THREE-WAY parity:
`checkpoint_complete.generation` == `r31p23_movement_completion.generation` == `r31p23r1_debug_queued.generation` == actual stdout completed lines with SAME PID/time_msec and FIFO order. `tests/tools/test_net_smooth1_r31p23r1_debug_fifo_audit.py` falsifies missing/reordered/wrong-generation stdout, missing M6 durable source, bad main-vs-wrapper PID, saturation, trace loss. This receipt does not rewrite raw traces nor turn original PERF_FAIL into PASS.

Existing strict P2.2/P23 reducer `analyze_r31p22_loop_stages.py` gains per-frame `deferred_debug_print_ms` and queue delay; if the shifted cost is greater than the observed same-frame original server process remainder, fail CLOSED. Never silently attribute it to OS/limiter or exclude frames.

## Mandatory exact source/native Windows verification

Fresh detached P2.3 R1 HEAD/TREE, explicitly compare merge-base to frozen parent #823 and tracked clean. Windows 10 DESKTOP-QNAGSTI, pwsh7.6+, Python3.11, Godot 4.7.1 stable double. Verify **wrapper SHA256** `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5` AND actual main engine EXE `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4` separately; version strings alone do not certify the main EXE. Real CC0 Quaternius 224 original files, no fallback. #820 external Job Guard own worktree, do not copy product source.

Cold import, Python R1 source/audit fixture suites and inherited P2.3/P2.2/P2.0/M6, new P23R1 Godot suite + all inherited 19 native M6/USER1/CHAR2 suites, exact Linux and Windows CI. Source CI PASS is not native PASS, queued jobs are not accepted.

## First real GUI — **two short matched 60s arms, NOT full release matrix**

Both OFF/ON on **same candidate R1 HEAD/TREE**, REAL server and two graphical Earth+Quaternius clients, LOCAL, OpenGL3 900x600, VSync OFF, 60 FPS, 10s warmup +60s measurement, distinct roots, external Job Guard receipts. Standard common flags both arms:

```text
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
--r31p23-completion-attribution
```

**R1 ON only additionally:** `--r31p23r1-defer-checkpoint-debug`. Thus OFF retains original synchronous debug and BOTH arms have IDENTICAL P23 completion instrumentation. Each arm must use same Godot/external assets/host load and run own unique root. Log first JOIN checksum failures as INCONCLUSIVE in issue #815; do not discard failed attempt or claim a functional PASS from a retry.

Run unchanged normative report and:

```powershell
python tools/net_smooth1/analyze_r31p22_loop_stages.py "<ON_RUN_ROOT>" --require-completion --output "<ON_RUN_ROOT>\p23r1_stages.json"
python tools/net_smooth1/validate_r31p23r1_debug_fifo.py "<ON_RUN_ROOT>" --output "<ON_RUN_ROOT>\debug_fifo_receipt.json"
```

Compare exact writer-completed generation count, stdout completion generation/PID/timestamp parity, bounded 32 FIFO, overflow=0, natural shutdown flush, same-frame moved print time and queue age, original normative server/client p99/p999/max and all >25ms frames. No p99 trimming or separate stage-percentile addition. OFF/OFF original debug_event_ms is expected, ON queued/debug_event_ms expected lower; if any new slow shifted print frame appears, report it in same-frame tail. Keep `CLEAN_JOB_EMPTY`, all three measure.end.ack, no foreign-process termination.

Only after successful 60s evidence and exact native reviewer may run **3 full paired 120s real GUI OFF/ON** on SAME later frozen R1 HEAD as a potential P2.3 R1 acceptance. All server+client p99<=25ms, p999<=50ms, max<=100ms, sim>=59Hz, 0 M6/ACK/replay/authority/ITEM/Resource checksums; 3 slow ITEM writer 1800ms, crash-kill/restart, seam A→B→A and stable connection. A short perf PASS does not authorize merge. Project Control canonical main drift, P7.4 base-equal phase-harness, SEAM-E2E and issue #815 remain separate blockers.

## Next target — COMPACT outbound_flush

P2.3 R1 only addresses measured completion debug overhead. Historical P23 R0 shows outbound_flush remains larger aggregate source of slow snapshot frames. A separate P2.3 R2 design must investigate NetworkTransportBoundaryV2 `flush_outbound` stages: existing frame bytes, extra `duplicate(true)`, `ProtocolFrameV2.validate()/encode()`, ENet `put_packet`, per-peer queue and coalescing, exact sequence/ACK/RESYNC constraints. Do not change transport order, drop packets silently, pre-encode future authority tick or use mutable live sessions in a worker. Select optimization by direct timing of the true expensive substep and independent RED/GREEN checksum/sequence/fault matrices.

**VERDICT: P2.3 R1 IMPLEMENTED_CANDIDATE / SOURCE_PASS / NATIVE_GUI_PENDING / PERF_FAIL inherited / READY_FOR_MERGE=false.**
