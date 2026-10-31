# NET-SMOOTH1 R31 P2.2 — server main-loop stage diagnostics (NO_MERGE)

## Frozen identity and independent evidence

Product parent: verified R31b P2.0 [PR #814](https://github.com/rootfabric/distributed-world-simulator/pull/814) exact HEAD `fdfbfb3b8dff911e6fd081a157652a28e1052cff`, TREE `585062871595267cbee4de38a1a8e41cec3a2605`. Original PR #814 remains Draft and unchanged; this P2.2 implementation has its own Draft PR/branch. P2.2 DOES NOT include the #816/#820 tooling commits in its product lineage; Windows Job Guard can be used independently as an external harness. No merge, no main changes.

Independent Windows #816 tail review on six #814 GUI runs: capture overlaps only 6.9–26% of p99 tail, noncapture p99 still 25.60–27.43ms; original overall server p99 26.3–28.3ms all FAIL versus <=25ms. Worst message aggregate windows show handler durations commonly only 1–7ms of 40–90ms; `message_ms` also includes precommit completion/admission/boundary poll. Some exceptions have actual 30–45ms packet handlers. Snapshot windows are often dominated by `compact_send_ms` (e.g. 84.5 of 109.8ms), but existing metric bundles frame construction, network send and outbound flush, not proof of an actual socket stall.

B3 independent Windows Job Guard smoke for [PR #820](https://github.com/rootfabric/distributed-world-simulator/pull/820) passed: portable 14/14, Win32 native 7/7, real Earth+Quaternius smoke Job natural empty after 19 owned PIDs, no forced termination, foreign processes untouched. The original runner FAIL 29.65ms p99 was preserved; B3 smoke PASS is NOT a 120s product performance PASS. Product does not incorporate B3 Job Guard automatically.

## P2.2 implementation: instrumentation ONLY, opt-in

`DWS_NET_R31P22_LOOP_ATTRIBUTION=1` / `--r31p22-loop-attribution` is SERVER-only, OFF by default. Requires the same fail-closed persistent USER1/R31a/R31b P0+P1/R2 stack as previous measurements, but P2.0 validator profiler may remain OFF to measure main-loop work without its overhead.

On each authoritative `_process()` when flag ON, NEW `r31p22_loop_stages` measures:
- postcommit stage drain, ITEM completion polling, movement checkpoint completion;
- deferred disconnect and deferred admission;
- boundary poll, handler dispatch, fixed simulation;
- movement snapshot publication, movement persistence and telemetry.

One frame-indexed event is emitted per successful server process frame; the original accepted scheduling, native M6/ACK/writer/checksum and `server_loop` timing/verdict are unchanged. The original frame probe gains `engine_frame=Engine.get_process_frames()` only with explicit flag. The server `server_loop` and `movement_snapshot_stages` records gain same-process frame IDs only in ON. They are NEVER used to join server clocks with client clocks.

The legacy `compact_send_ms` is decomposed for each successful COMPACT_GAMEPLAY_SNAPSHOT send into `payload_clone_ms`, `frame_create_ms`, `boundary_send_ms`, `outbound_flush_ms` and total. Failures emit explicit `r31p22_compact_wire_failed`; no socket or worker semantics modified and no new frame payload fields are sent to clients. These are synchronous main-thread API durations, NOT network transmission/receive latency.

Python `analyze_r31p22_loop_stages.py`: validates complete trace header/sequence/footer/drop count, positive same-process engine frame IDs, matches frame/server_loop/P2.2 source and snapshot/COMPACT wire rows by exact engine frame, fail-closes incomplete (>1%) joins, impossible stage sums or send errors, reports p50/p95/p99/max and exact worst intervals. It preserves original report verdict and never excludes a slow frame to claim normative PASS. `uncovered_probe_interval_ms` is not proof of OS/limiter sleep.

## Exact local Windows source/native gates

Fresh detached worktree at this P2.2 PR exact HEAD/TREE (not historical #814 head); canonical Quaternius CC0 assets with real avatar provider and texture aliases, Godot 4.7.1 stable double. Hash console wrapper and **main** binary separately; canonical wrapper SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, main observed `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`. Merely matching the version string is NOT exact provenance.

- Cold import; native `tests/runtime/test_net_smooth1_r31p22_mode_guard.gd` tests invalid mode, missing full canary stack, ON and default OFF.
- Python `tests/tools/test_net_smooth1_r31p22_loop_stages.py` and `test_net_smooth1_r31p22_source_contracts.py` plus inherited P2.0/P1/M6 suites and independent Windows/Linux CI.
- Verify real two-client output is valid: zero M6/ACK/replay/authority violations, no introduced COMPACT frame checksum mismatches, graceful 3-role measurement.end ACKs and Job Guard isolation receipt when using separate #820 tool.
- A source/native PASS is **not** a GUI performance PASS.

## First Windows experiment: ONLY short, focused diagnostics

DO NOT spend six 120s runs before locating the costly stage. Use same NEW P2.2 product HEAD, real Earth+Quaternius two-client GUI, OpenGL3 900x600, VSync disabled, 60fps, LOCAL, same canonical R31 roundtrip.

First ONE ON measured 30–60s, warmup10, server-only `--r31p22-loop-attribution`. Common flags:

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
```

Use #820 Job Guard as an EXTERNAL supervisor with exact TOOLS_HEAD `b4cbf565764cea16eb81cc163824b2a237e2cb8a` and an independent Job receipt. Do not cherry-pick it into product branch. Preserve original runner FAIL exit, even on a short sample.

After run, use:

```powershell
python tools/net_smooth1/analyze_r31p22_loop_stages.py `
  "<OUTPUT_ROOT>" --output "<OUTPUT_ROOT>\r31p22_loop_attribution.json"
```

Report same-engine-frame join coverage, top-100 frame substage times and p99 non-snapshot tail, which stages dominate the top-1% *frames*, compact frame_create versus flush versus network send, observed precommit/completion/admission versus actual dispatch. Do not claim OS wait from the uncovered interval. If trace syntax/framing fails, capture actual events, mark INCONCLUSIVE and repair tests WITHOUT modifying old evidence.

Then, only if stage data are complete, ONE comparable OFF 30–60s run on SAME product HEAD with P2.2 flag omitted and same host load, to estimate observer overhead. A short run never certifies normative 120s p99. **No 3-pair full GUI acceptance at this diagnostic stage.**

## Decision / next product repair

Pick one measured candidate based on overlap with worst server frame tail, not the largest independent stage p99:
1. If postcommit/admission/completion dominates, create separate scheduling work order with M6 ACK escrow and durable-before-ACK preserved; don't unbound drains.
2. If `frame_create_ms` dominates COMPACT sends, inspect canonical serialization / duplicate JSON in the boundary. If `outbound_flush_ms` dominates, examine bounded per-peer ENet flush; don't silently change packet delivery semantics.
3. If `boundary_poll_ms` dominates, measure boundary event count and shape / batching. If `message_dispatch_ms` dominates, tie `server_message` durations to that same engine_frame; do not call all time socket receive.
4. If uncovered dominates, run separate frame-cadence/engine scheduling experiment. Never change 60Hz simulation, max 60FPS cap or p99 norm solely to pass.

Production release still requires 3 paired 120s real GUI ON/OFF same exact implementation HEAD of a **later performance repair**, original server+both clients p99<=25ms, p999<=50ms, max<=100ms, server sim >=59Hz; 0 M6/checksum/replay/ACK/authority errors, 3 slow ITEM 1800ms, hard-kill/restart, seamless A→B→A, fresh source/native Linux/Windows, origin of main+console binaries, Project Control owner/main drift and separate SEAM-E2E. Issue #815 intermittent pre-measure PAYLOAD_CHECKSUM_MISMATCH remains open.

VERDICT: P2.2 DIAGNOSTIC_IMPLEMENTED / PERF_FAIL inherited / NO_MERGE. #814, #816, #820 unchanged.
