# NET-SMOOTH1 R31b P1 R2 — Windows signed instance-id + owned-process cleanup

## Frozen identity and scope

Base: immutable R31b P1 Safety R1 Draft PR #803 at HEAD 6cdb0f0ce0f8550ece723194d67826afc6b81348, TREE 1d3401290cf3097c3ee13c90775d569883cacfa5. New R2 is a separate ahead-only branch, NOT merged into #803 or #802/main. Corrected P0 #799 exact e75ec0e32c5d1b38b1c32526aa56407aa2fb4716.

Independent #803 GUI report: 3× OFF/ON 120s real two-client Earth+Quaternius functional PASS, but server frame p99 60.9–71.7ms, clients 33–38ms and server max up to 777ms, all PERF_FAIL. P1 active-seam M4/Resource cache showed Δhits=60–61, Δmiss=0, bypass=0, and M4 p50 ~0.11–0.13ms. However normative P1 analyzer rejected real negative Win64 Godot Object.get_instance_id(); first ON was contaminated by a leftover Godot process after a previous FAIL. CPU host load 81–93%; historical late t≈120.5s spikes across server and two clients may coincide with measurement end/final teardown but are not automatically waivable.

## R2 fixes

### B1 signed Win64 instance_id — evidence only

The instance_id is an **opaque signed 64-bit nonzero identity** returned by Godot, not a positive index. Negative signed values (e.g. -9223371846030719459) are legitimate Win64 instances and must pass input validation **unchanged**. The analyzer rejects zero, non-int (including bool), out-of-i64 range; retains exact kind, owner, epoch, revision/tick/generation and monotone source_serial invariants, measured-window hit/miss deltas, memory and explicit bypass checks. DO NOT use abs() (would change equality semantics), rename the field, weaken checksum/fence or alter the native game.

New positive/negative Python fixtures validate this exact Win64 value, zero, string, out-of-range. Re-run the unmodified three old #803 ON traces with this NEW reducer, save original trace hashes and new r31bp1_chunks.json separately. Historical GUI metrics do not change retroactively. No new GUI required for B1.

### B3 exact owned-run process cleanup

A single Godot console-wrapper Popen.wait() is insufficient on Windows: the main Godot exe can remain alive after its wrapper exits. New stdlib-only tools/net_smooth1/owned_process_cleanup.py:

- Detects Godot process names by Windows CIM, checks exact --instance-id=16hex AND --node-id=smooth-(server|a|b)-same-id and canonical Godot executable folder.
- Never uses taskkill /IM; tree termination uses taskkill /PID <verified-run-owned-pid> /T /F only, followed by a second read-only Windows CIM check.
- Unverified executable path, role mismatch, query failure or still-live process => FAIL/INCONCLUSIVE, never a clean PASS; no killing other projects, normal editors, unrelated run IDs, different Godot binary directories.
- Adds per-run manifest.cleanup with verified, forced role, orphan, PID and cleanup status. Any recovered orphan is an error in its own run; a subsequent arm may proceed only if no owned Godot processes remain.
- Before a GUI run, preflight refuses any existing net_smooth1 Godot started from same Godot binary directory, rather than silently contaminate paired performance.

Cleanup executes on success or failure, and preserves runtime errors, manifest and raw trace. The original R31 P1 flags/benchmark thresholds are untouched.

### End-of-measurement ACK fence (do not reclassify old >100ms data)

The Godot NetSmoothProbe responds to existing per-role measure.end with a new measure.end.ack file **only after** Trace.measuring=false; runner waits for all server/a/b ACKs before any final screenshot, planned reconnect or teardown. Missing/malformed ACK => INCONCLUSIVE. No arbitrary 0.5/1.2 sec sleep is used as evidence of measurement closure. This DOES NOT discard a real stall that happened before the probe acknowledged the fence or rewrite old traces; it only strengthens future measurement boundary consistency.

Source tests/falsifiers cover exact run scope, no wildcard kill, legitimate unrelated editor, kill/timeout/query failure, generated ACK ordering, original R31 full measurement duration and normative thresholds. Native parse and real Windows GUI still independently required.

## Independent Windows work order

Host: DESKTOP-QNAGSTI Windows 10 PowerShell 7.6, Python 3.11, Godot 4.7.1 double. Pin console wrapper SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5; also report main executable actual SHA 6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4 and independently establish its reference before claiming full binary exact. Real Quaternius assets (no fallback). Worktree must be fresh detached and pinned to new R2 HEAD/TREE.

1. Source/Windows pinned native exact CI on exact R2 HEAD. Explicitly run Python tests test_net_smooth1_r31bp1_durable_chunks.py, test_net_smooth1_owned_process_cleanup.py, test_net_smooth1_r31bp1_b1b3_contracts.py and inherited M6, USER1, R31b P1 native parity. Preserve known P7.4 base-equal port-9081 issue separately.
2. **B1 historic read-only reanalysis** of old #803 evidence ON roots under C:\EVIDENCE (pair1-on/2-on/3-on). Re-run only analyzer on exact old raw trace.jsonl from each ON root using new script; expect original native negative instance_id accepted, 100% measured-window M4/Resource hits and bypass 0 if raw reports unchanged. Save new reducer outputs as separate files with old HEAD plus new-tool HEAD metadata. If a new error occurs, DO NOT massage traces; report and repair.
3. **B3 one short real GUI negative** (deliberately injected fault or bounded synthetic early failure), ensure cleanup verified and no Godot with that run_id in CIM. Do not kill other Godot users. Then one 30s 2-client GUI smoke validating server/a/b measure.end.ack, measured frame duration, nonzero trace samples, no lingering Godot child after FAIL/PASS, manifest cleanup, and unchanged avatar provider.
4. Only once host load is controlled, repeat the 3× matched **120s 2-client Earth+Quaternius P1 OFF/ON** performance pairs on this new R2 HEAD. R31a+P0 common flags both; ON alone --r31bp1-durable-chunks. Record host CPU usage, idle GPU, PowerShell/Windows process occupancy and start/end uptime. Do not silently close user apps; ask operator if host load is too high. Preserve every PERF_FAIL.
5. Normative thresholds unchanged: server and both clients p99<=25ms, p999<=50ms, max<=100ms, simulation>=59Hz, 0 M6/ACK/replay/checksum violations, complete traces. A >100ms gap during still-open measurement is a failure, not a waiver. Separately analyze t≈120.5s clusters and compare explicit measurement end ACK to actual runtime stop.

## P2 workstream (separate, not in this branch)

The remaining P1 ON gameplay validation p50 11.6–14.3ms, p99 ~23–37ms under high host load remains a prospective optimization. First P2.0 must separately time immutable component checks, player/ownership consistency, global checksum and JSON-safety; only then consider version-fenced validation attestations for M4/Resource chunks while retaining outer checksum and live cross-domain validations every tick. Never merely skip validate_durable_state() or move live data across frames/threads.

No main changes, no merge/force-push, no norm waivers. Project Control CANDIDATE_MAIN_DRIFT and SEAM-E2E remain separate release gates.
