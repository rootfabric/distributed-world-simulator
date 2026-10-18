# NET-SMOOTH1 R3C.4 R1 — bounded periodic checkpoint frame headroom

## Purpose and exact base

Parent: PR #785 `2b0e4848f498d0163ce81785073a9624649d14b8` — independent Windows/Linux exact and 3×120s R31 GUI NARROW_VERIFIED.
Branch: `feature/net-smooth1-r3c4-periodic-frame-headroom-r1`.
**This is a performance candidate, not accepted release performance.** `main`, M6 schema, shared async writer, command/ITEM durability/ACK escrow, and client Earth/Quaternius code are unchanged.

## Root-cause hypothesis grounded in verified Windows evidence

R31 GUI p99 server 40–41ms and p999 55–57ms on identical 60fps environment; 90/93 gaps >40ms occur near `periodic_checkpoint_dispatch/capture/complete`. Current server _process invokes `_maybe_publish_movement_snapshot()` (20Hz full snapshot + compact) directly before `_maybe_persist_movement_checkpoint()` every 1500ms; 1500ms is exactly 30 network snapshot periods of 50ms. This systematically stacks expensive M6 authority/replay capture with snapshot serialization on one frame.

R3C4 R1 performs **frame separation only**, not multi-frame semantic snapshot creation (unsafe without a frozen value view). Uses server-only opt-in `DWS_NET_R3C4_PERIODIC_FRAME_PACING=1` / harness `--r3c4-periodic-frame-pacing`. Default off preserves exact preexisting behavior.

1. Record whether a 20Hz snapshot was prepared in the current server process frame and how much main-thread pre-capture work elapsed.
2. If periodic snapshot is due on the same heavy frame, defer once while dirty data remains live. Next low-work frame uses the original `_recovery_authority.export_recovery_state()`, `_replay_outbox.to_dict()`, `AsyncCheckpointWriter.submit()` single-writer pipeline unchanged.
3. Force a due capture no later than the next eligible process frame after **64ms**, even if busy, preventing workload-dependent starvation.
4. An existing busy worker defers by the original single-writer backpressure; this policy never creates an alternate generation or clears dirty before a successful submit.
5. All stage events are process-local trace metadata. No uncommitted data is sent, no worker copies/live aliases are relaxed. Synchronous durable commands and their `durable-before-ACK` barrier are untouched.

## Exact native falsifiers

- `tests/runtime/test_net_smooth1_r3c4_periodic_frame_headroom.gd`: real M3 persistent runtime, default-off parity, opt-in first deferred heavy frame, low-work frame submit, strict completion generation and ACK gate parity, forced bounded capture, disk restore, shutdown, invalid mode rejection.
- `tests/tools/test_net_smooth1_r3c4_periodic_frame_headroom_source.py`: guarded source/fault-mutant tests.
- Pin Windows/Linux 4.7.1 double SHA; cold import, new falsifier and retained existing M6/slow ITEM/recovery and staged Earth suites. CI source and native PASS needed before GUI tests.

## Real Windows GUI paired acceptance (mandatory)

Fresh dedicated Windows DESKTOP-QNAGSTI, same renderer OpenGL3 900x600 VSync disabled 60fps, same Quaternius assets, pinned Godot SHA.
Runs must be 120s **real measured window**, HEAD+TREE identical for baseline and candidate, 2 real GUI clients + dedicated server and 20Hz authoritative simulation:

Baseline R3C.4 flag OFF, candidate R3C.4 flag ON with exactly identical other flags:
```powershell
$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Common=@('--godot',$Godot,'--mode','gui','--duration','120','--warmup','20','--scenario','r31-reconnect-roundtrip','--r3c-async-admission','--r3c2-avatar-prewarm','--r3c2-server-phased','--r3c3-staged-earth','--r3c21-frame-paced-presentation')
# run each in the frozen feature branch worktree; output directory must not exist
python tools/net_smooth1/run_net_smooth1.py @Common --output 'C:\dws-r3c4-r1-baseline-1'
python tools/net_smooth1/run_net_smooth1.py @Common --r3c4-periodic-frame-pacing --output 'C:\dws-r3c4-r1-enabled-1'
```
Run 3 paired baseline/enable repeats and 3× candidate `--scenario r3-slow-item --slow-item-writer-ms 1800` with the flag, plus restart, replay ordering, stale completion, durable-before-ACK, checksum, recovery invariants.

Analyzer `tools/net_smooth1/analyze_net_smooth1.py` is **unmodified**: client/server p99<=25ms, p999<=50ms, client max gap<=100ms, server loop>=59Hz, 0 fatal, 0 replay/ACK loss and 0 dropped trace. Check frame spikes at `r3c4_periodic_frame_deferred`, `r3c4_periodic_capture_slot`, `checkpoint_capture`, `checkpoint_complete`; prove same number/order of durable generations and no worse recency than 64ms deferral vs baseline.

If periodic p99 still fails, report `PASS_WITH_FINDINGS / PERF_FAIL` and proceed with a **separate R3C.4 R2** design for splitting expensive immutable export/checksum capture across frames; do not weaken duration, cadence, M6 or other invariants. Separate synchronous command drain (970ms) needs the independent M6 Work Order, not an implicit change here. Project Control generation 82->83 rotation remains canonical owner responsibility (#783).

No merge / rebase / 4h soak without independent review and GUI evidence.
