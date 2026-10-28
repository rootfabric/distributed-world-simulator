# NET-SMOOTH1 R31 P1: Windows exact product server-frame pacing — Work Order R1

## Purpose / source identity

Verify Draft PR #859 as a candidate final HEADLESS server frame-loop setting. Direct ancestry: Draft #858 diagnostic HEAD 4a223cf3362fc9a6585420c23dba68a8e7bdca0b → PR #859. Base Windows reporter had 7 native + 35 focused PASS but six GUI server p99 25.23–27.73ms FAIL (including two >100ms gaps). Nothing in that previous campaign authorizes a 120-FPS product default.

Freeze the **current PR #859 HEAD + TREE from GitHub** into clean detached product worktree and do not mix with a separate B3 Job Guard PR #820 tools worktree HEAD b4cbf565764cea16eb81cc163824b2a237e2cb8a. No rebase/merge/force, no main mutation or threshold change.

## Product implementation to verify

- Explicit server-only application launch option --server-frame-cap=60/90/120; default 0 means **no native Engine.max_fps mutation**. Strict dedicated-server + network-mvp + product-seam + world earth. All client/listen-host/other modes and unsupported caps fail closed.
- The original runner launches the dedicated server with --headless --disable-vsync and now sets Godot --max-fps to 60 or 120, plus product --server-frame-cap=120 **only** on the trial arm. The actual server must print precisely one native receipt NET_SMOOTH_SERVER_FRAME_CAP_APPLIED cap=120 fixed_tick_hz=60 compact_hz=20; 60 baseline has no explicit product receipt. Client A and B remain OpenGL3 GUI, 60FPS and no server-frame-cap.
- The product fixed tick stays **60Hz**, COMPACT publication **20Hz**; wire, ownership epoch, checksum, USER1, M6 durable-before-ACK and OUTBOX/replay do NOT change. The strict comparator must reject any missing receipt/canary or checksum/authority regression.

## G0: Windows exact preflight

Real Windows native Session 1 + RTX 4060 with hardware OpenGL3 and quiet host; do not terminate foreign Godot/Actions processes. Pin Godot 4.7.1 stable double console SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5. Hash actual real main EXE against historical trusted evidence independently; wrapper hash alone cannot prove its identity.

Quaternius: **123 raw source files**, plus 101 .import sidecars historically; never require 224 RAW. Verify full raw per-file hash against trusted historic pack and identical asset_manifest_sha256 across six arms. Keep 20-second ambient CPU/process/GPU receipts per arm. If host contended, stop or label data HOST_CONTENDED and never accept it as final normative pass.

Run exact zero-error cold import; nine native focused scripts including test_net_smooth1_product_server_pacing, test_launch_options, actual real-boundary partial transport, P1 batching, safety #815 negatives, R2.2 COMPACT, R2.1 legacy, M6 recovery and USER1 product seam. Then full focused suite. All zero ERROR/Parse/Compile and exit 0 before perf.

## G1: six real GUI native 120-second paired runs

Run checked-in tools/net_smooth1/run_r31_final_pacing_windows.ps1 from exact product checkout. It requires Product path, separate GuardTools path, NEW Evidence path, immutable ExpectedHead/ExpectedTree and optional CandidateCap=120. Script fails closed on wrong product/Godot/tool SHA, raw asset count, lost ACK, dirty worktree and Job Guard containment; each native FAIL report is retained, not recast as PASS.

Example (replace HEAD/TREE values with current frozen PR #859 HEAD/TREE; directory paths are local examples, not fabricated verified directories):

~~~
pwsh -NoProfile -File .\tools\net_smooth1\run_r31_final_pacing_windows.ps1 -Product C:\dws-final-pacing-product -GuardTools C:\dws-b3-guard-tools -Evidence C:\EVIDENCE\R31_PACING_FINAL_R1 -ExpectedHead EXACT_PR859_SHA -ExpectedTree EXACT_PR859_TREE -CandidateCap 120
~~~

Order: p1 60→120, p2 120→60, p3 60→120. Each arm 20s warmup, 120s measured, LOCAL, r31-reconnect-roundtrip, server dedicated HEADLESS Earth+product-seam, 2 real graphical Earth Quaternius clients, real movement A→B→A and B reconnect. The measured interval starts after functional roundtrip. All arms run P1 batching + R2.2 attested ON, R31BP1 durable and R3C4 worker/replay; **ONLY server cap changes**.

Common runner flags maintained EXACTLY for every arm:

~~~
--mode gui --scenario r31-reconnect-roundtrip --duration 120 --warmup 20 --profile LOCAL
--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased
--r3c3-staged-earth --r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing --r3c4r2-worker-envelope
--r3c4r31-replay-projection --r3c4r31b-durable-attribution
--r31bp1-durable-chunks --r31p22-loop-attribution
--r31p23r2-flush-attribution --r31p23r21-single-pass-compact
--r31p23r22-attested-compact
~~~

Require raw original 3 process traces, report.json, manifest.json, Job Guard receipt with CLEAN_JOB_EMPTY, all 3 measure.end.ack, 20Hz batching, 60Hz authoritative tick, no dropped simulation time, no unexplained >100ms frame gap and exact six unique run IDs; all source/binary hashes and host CPU/GPU inventory. Do not skip a failing run or change the cap mid-run. Exit code 1 due to original PERF_FAIL must remain FAIL even when job cleanup is clean.

## G2: independent evaluation / anti-percentile-dilution

Read-only compare_r31_server_pacing.py must report, per baseline/trial pair:
- Original normative server and clients frame p99<=25ms, p999<=50ms, max<=100ms and server simulation>=59Hz.
- Absolute server counts of **>25ms / >50ms / >100ms intervals per measured SECOND** as well as p99. Adding empty 120FPS iterations can lower a percentile without improving real movement: this is NOT acceptable proof.
- 20Hz COMPACT packet batch/same session/sequence/authority and M6/ACK/OUTBOX. Clients unchanged at 60FPS/OpenGL3, no first-JOIN checksum mismatch and no unexpected disconnect.
- CPU budget, ambient load and tail attribution. Same HEAD/TREE/assets/binary/flags for all six arms. Candidate should improve absolute stall rate without worsening clients. Cross-process simultaneous OS stalls cannot be blamed on GPU/VSync/ENet without evidence.

If all THREE candidate 120 runs really meet each original bound with independent review and genuine stall-rate improvement, label WINDOWS_GUI_CANDIDATE_PASS; not MERGE_READY. Otherwise PERF_FAIL. If 120 adds CPU contention or does not improve actual gaps/s, record failure; optional 90 cap may be tested in a NEW equally controlled 3-pair matrix, not silently swapped into this one.

## Final publication

Publish full run SHA inventory, 6 raw run roots/unique IDs, HEAD/TREE and two Godot binary hashes, asset SHA, 9 native scripts + focused source/evidence, 3x(server/client p99/p999/max and 59Hz), batch ~20Hz, >25ms gaps/s, JOIN/M6/ITEM/USER1/ACK/authority state, exact Project Control and Linux exact check IDs to PR #859 and WO #850.

Verdict is factual. No automatic merges, no source threshold edits, no pre-emptive 120FPS default, issue #815 root cause UNKNOWN, PC0 CANDIDATE_MAIN_DRIFT and true multi-host SEAM-E2E separate. READY_FOR_MERGE=false.
