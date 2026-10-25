# NET-SMOOTH1 — R3 server headless pacing 60/90/120: Windows diagnostic Work Order

## Goal / immutable identity

Independent Windows evidence [PR #857](https://github.com/rootfabric/distributed-world-simulator/pull/857#issuecomment-6393594130) reported 7/7 native PASS and 35/35 focused PASS after two **test-only repairs** on `repair/net-smooth1-p1-windows-exact-type-r1` exact HEAD `6b7b2a25cb5f1525a41e64c31b1c9600c399d44d`. GUI server frame p99 25.23–27.73ms FAIL in six 120s arms, two >100ms tail events. User1 A→B→A and clients functional PASS. Historical #815 and Project Control separate.

**Technical finding:** Existing `tools/net_smooth1/run_net_smooth1.py` launches the dedicated SERVER with `--headless --max-fps 60 --disable-vsync`; BOTH clients run 60fps `opengl3` GUI. `scripts/network/simulation/fixed_tick_scheduler.gd` independently holds authoritative 60Hz. Headless server has no graphics VSync, so 16.7/33.3ms frame quantization is not proof of VSync stall. This diagnostic tests the engine frame limiter versus available headroom without touching the fixed simulation frequency, packets or clients.

Freeze this diagnostic branch on exact HEAD/TREE emitted by GitHub after creation, and use that SAME HEAD for every arm. The branch is **strict child** of verified Windows repair `6b7b2a25...`. It changes ONLY external Python GUI test harness/source tests/docs/workflow, never Godot runtime/wire, USER1/M6, auth epoch or frame thresholds. Legacy CLI default `--server-max-fps 60` is byte-identical with prior original `--max-fps 60` server argv. Clients are always 60. Candidate 90/120 is explicit test-only; no production activation.

## G0 — Windows preflight

Host DESKTOP-QNAGSTI or equivalent native Windows, interactive Session 1 with RTX4060 and actual OpenGL3 graphical client windows. Godot 4.7.1 double console SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`. Record actual main exe hash, tool/product HEAD and TREE, source-asset pack 123 RAW files plus 101 `.import` sidecars and full original SHA map. Run Godot import and 35 focused/native safety tests on current checkout. Use external job-containment [#820](https://github.com/rootfabric/distributed-world-simulator/pull/820) with its exact tool SHA `b4cbf565764cea16eb81cc163824b2a237e2cb8a` in ANOTHER worktree. Never stop an unrelated Windows runner or foreign Godot manually. CPU/GPU/process inventory 20s before each run; if contended, label HOST_CONTENDED, seek a clean slot.

## G1 — six exact two-client real GUI arms

Order for the FIRST 60-vs-120 confirmation (not release acceptance): `p1-cap60 → p1-cap120 → p2-cap120 → p2-cap60 → p3-cap60 → p3-cap120`. Each arm = 20s warmup, 120s measurement, `--mode gui --scenario r31-reconnect-roundtrip --profile LOCAL` with real Earth+Quaternius server/2 clients and original Windows Job Guard. Both caps use R2.2 ON, batching ON, all other canary flags identical. Only DIFFERENCE is `--server-max-fps 60` versus `--server-max-fps 120`.

````powershell
$Common=@(
  '--mode','gui','--scenario','r31-reconnect-roundtrip','--duration','120','--warmup','20','--profile','LOCAL',
  '--r3c-async-admission','--r3c2-avatar-prewarm','--r3c2-server-phased',
  '--r3c3-staged-earth','--r3c21-frame-paced-presentation',
  '--r3c4-periodic-frame-pacing','--r3c4r2-worker-envelope',
  '--r3c4r31-replay-projection','--r3c4r31b-durable-attribution',
  '--r31bp1-durable-chunks','--r31p22-loop-attribution',
  '--r31p23r2-flush-attribution','--r31p23r21-single-pass-compact',
  '--r31p23r22-attested-compact'
)
$Python=(Get-Command python).Source
$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Product='C:\dws-pacing-r1'   # fresh exact detached worktree at the diagnostic HEAD
$Guard='C:\dws-b3-tools'   # separate exact #820 tools worktree
$Out='C:\EVIDENCE\R31_SERVER_PACING_R1_'+(Get-Date -Format yyyyMMdd-HHmmss)
New-Item -ItemType Directory -Force $Out | Out-Null
foreach ($Arm in @('p1-cap60','p1-cap120','p2-cap120','p2-cap60','p3-cap60','p3-cap120')) {
  $Cap=if ($Arm.EndsWith('cap60')) {60} else {120}
  $Folder=Join-Path $Out $Arm
  New-Item -ItemType Directory -Force $Folder | Out-Null
  $Receipt=Join-Path $Folder 'job_receipt.json'
  $Run=Join-Path $Folder 'run'   # Must NOT pre-create; original runner owns it
  & $Python (Join-Path $Guard 'tools\net_smooth1\run_r31_job_guard.py') `
     --receipt $Receipt --cwd $Product --deadline 1800 -- `
     $Python (Join-Path $Product 'tools\net_smooth1\run_net_smooth1.py') `
     --godot $Godot --output $Run --skip-import `
     --server-max-fps $Cap @Common
  # Preserve all original verdicts. PERF_FAIL causes runner/Job Guard exit 1.
  # Independently require Job receipt job_cleanup.acceptance == CLEAN_JOB_EMPTY,
  # all three measure.end.ack, original manifest/report, 3 traces/END/sha256,
  # both real CONNECTED clients and no checksum/M6/authority/OUTBOX errors.
  # Abort if any safety, trace, identity, process isolation or parse/compile error.
}
python (Join-Path $Product 'tools\net_smooth1\compare_r31_server_pacing.py') `
  --pair (Join-Path $Out 'p1-cap60\run') (Join-Path $Out 'p1-cap120\run') `
  --pair (Join-Path $Out 'p2-cap60\run') (Join-Path $Out 'p2-cap120\run') `
  --pair (Join-Path $Out 'p3-cap60\run') (Join-Path $Out 'p3-cap120\run') `
  --output (Join-Path $Out 'pacing-comparison.json')
````

**Important:** These sample commands presuppose the independent exact identity, import, CPU idle and guard checks in G0 are already done; they must not be used to bypass them. Their output locations are illustrative and must be verified, not inferred. Re-run only in a new evidence directory. Never treat `GUARD_FAIL` due solely to original PERF_FAIL as successful performance; only `CLEAN_JOB_EMPTY` proves process isolation.

## G2 — acceptance / falsification

1. Original `report.json` and ALL process traces remain authoritative; old thresholds unchanged: every server and client frame p99≤25ms, p999≤50ms, max≤100ms, server tick≥59Hz, zero dropped time and no unexplained >100ms gap. ALL six attempts retained, including FAIL/INCONCLUSIVE.
2. 120-second server COMPACT batching cadence must remain ~20Hz (19–21 per measured second) despite more engine frames; native authority itself remains 60Hz, same revision, session/sequence, packet channels, checksum and M6 durable-before-ACK. Clients remain at 60fps and GPU-rendered.
3. Evaluate two metrics side by side: true server frame p99 and **absolute count of >25ms gaps per measured second**. Increasing engine frame frequency can dilute percentile with extra empty frames; apparent p99 win WITHOUT improvement in slow-gap rate is NOT sufficient evidence of smoother gameplay. Also compare p999/max, server process time, CPU, 20Hz packet count, client p99 and remote movement.
4. If FPS120 saturates CPU, creates >100ms stalls, degrades clients or breaks 59Hz/20Hz cadence, revert diagnostic, do not integrate into production. Consider cap90 only as a separate exact A/B experiment with new independent receipts.
5. The cause of ~16.7ms quantization could be max-FPS pacing/OS timer/scheduling; this A/B does NOT prove which mechanism without additional ETW/CPU evidence. Server is already headless; never claim VSync present merely because frame intervals quantize.
6. Even an all-green 120fps experiment does NOT authorize a merge: #815 ROOT_CAUSE_UNKNOWN, Project Control CANDIDATE_MAIN_DRIFT, Linux Exact, real multi-host SEAM-E2E must still be independently addressed. All PRs Draft, main untouched.

## Outputs

Exact source and binary hashes; six distinct run IDs; original per-role p99/p999/max and 60Hz simulation; 20Hz batch count; >25ms gap RATE/s; client Quaternius proof; all original traces and SHA256 manifests; JobGuard receipts, CPU/GPU inventory; native source test results; independent reviewer report. Verdict `PACING_DIAGNOSTIC_INCONCLUSIVE`, `PACING_NO_BENEFIT`, or `PACING_BENEFIT_NEEDS_RELEASE_GATES`; never invent `PERF_PASS` based only on this comparator.
