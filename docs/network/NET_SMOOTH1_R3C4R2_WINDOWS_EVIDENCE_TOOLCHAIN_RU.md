# NET-SMOOTH1 R3C.4 R2 — Windows independent GUI evidence toolchain (support only)

**Do not modify or merge candidate PR #787 during measurement.**
Pinned HEAD: f64fed2430f1292773d1561f881e5c8a4cc89075
TREE: 01731ee75418c58c2f2d2e16fb39d29b9a167def
Parent: ced03db64eae3adaab270044574c0f8b96c590c6.

The goal is **3 matched, 120s, Windows GUI Earth+Quaternius 2-client pairs**
(R1-only OFF vs R1+R2 ON), plus **3 slow-ITEM scenarios** (1800ms writer injection).
Do not alter normative analyzer or its 25/50/100ms and 59Hz thresholds.

## 1. Setup on DESKTOP-QNAGSTI (PowerShell 7.6+, Python 3.11)

Use a clean checkout and trusted Quaternius asset package. External assets may
not be in Git: ensure 220+ complete files, correct glTF texture URIs, and no
fallback avatars. The runner verifies frozen Godot version and SHA256.

~~~powershell
$Repo = 'C:\dws-r3c4r2-787-exact'
git clone https://github.com/rootfabric/distributed-world-simulator.git $Repo
Set-Location $Repo
git fetch origin --prune
git checkout --detach f64fed2430f1292773d1561f881e5c8a4cc89075
# Copy verified Quaternius assets to assets/external/quaternius.
# Do not modify tracked files or use fallback assets.
~~~

Fetch support tools **outside** the exact candidate worktree (no cherry-pick).
Record their separate HEAD and SHA256.

~~~powershell
$Branch = 'work/net-smooth1-r3c4r2-independent-gui-evidence-r1'
$RefSpec = 'refs/heads/' + $Branch + ':refs/remotes/origin/' + $Branch
git fetch origin $RefSpec
$ToolDir = 'C:\dws-r3c4r2-tools'
New-Item -ItemType Directory -Force $ToolDir | Out-Null
$RunnerPath = Join-Path $ToolDir 'run_r3c4r2_windows_acceptance.ps1'
$ComparePath = Join-Path $ToolDir 'compare_r3c4r2_gui_evidence.py'
git show ('origin/' + $Branch + ':tools/net_smooth1/run_r3c4r2_windows_acceptance.ps1') |
    Set-Content $RunnerPath -Encoding utf8
git show ('origin/' + $Branch + ':tools/net_smooth1/compare_r3c4r2_gui_evidence.py') |
    Set-Content $ComparePath -Encoding utf8
Get-FileHash $RunnerPath -Algorithm SHA256
Get-FileHash $ComparePath -Algorithm SHA256
~~~

Run in a real interactive Windows desktop session. New evidence path each time.

~~~powershell
$Out = 'C:\dws-r3c4r2-787-evidence-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
pwsh -NoProfile -File $RunnerPath -RepoPath $Repo -OutputRoot $Out -GodotPath 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
~~~

Launcher operations: fail-closed identity, ancestry, tracked clean, Godot SHA,
220+ Quaternius files, focused + R2-specific source/native tests, 3 alternating
OFF/ON, ON/OFF, OFF/ON full R31 GUI pairs, 3 slow ITEM canaries, repeat normative
analysis, compare stages, hash all generated evidence. An individual perf exit
code 1 does NOT abort the remaining valid run batch.

## 2. Outputs / verdict

OutputRoot contains:
- identity.json, sha256.json; focused/, r2-native.log
- gui-off-1..3, gui-on-1..3 (full per-process traces and reports)
- slow-item-on-1..3
- comparison.json and comparison.md

Reducer exit:
- 0 = GUI_PERF_GATE_PASS_ONLY, still NO_MERGE
- 1 = PERF_FAIL, still NO_MERGE
- 2 = INCONCLUSIVE, still NO_MERGE
- 3 = FUNCTIONAL_FAIL, still NO_MERGE

Checks: pinned identity, Windows GUI/LOCAL, complete R31, 120s manifest duration
and measured coverage, same asset hash, same mode flags except R2; frame thresholds
server/client p99<=25ms, p999<=50ms, max<=100ms, server loop>=59Hz.
Compares checkpoint_capture authority_ms and handoff_ms versus worker wrap_ms,
build_ms, write_ms, plus frame distributions. It never downgrades the normative
analyzer or changes any accepted candidate code. No result automatically merges.

## 3. Separate required human/integration gates

The launcher cannot certify crash/restart, real durable-before-ACK, ACK escrow,
generation order or replay parity. Execute these as **separate R2-enabled**
fault-injection tests, publish disk, journal and operation-ledger evidence and
verify exact R2 flag in trace.

Existing tools/net_smooth1/fault_kill_miditem.py sets DWS_NET_P1B_ITEM_ASYNC
but does **not** explicitly enable R3C.4 R2; its PASS is NOT sufficient
evidence for the new periodic-worker path. Adapt only in an isolated verifier
without modifying candidate HEAD. Inspect 3 slow-ITEM reports for >=24 real
durable operations, ACK/commit correctness, replay idempotence and checksum;
manifest.completed alone is not durability proof.

Project Control generation rotation remains with canonical owner (#783). No
waivers. Independent reviewer required. SEAM-E2E remains separate mandatory
program.

If R2 GUI p99 still >25ms: publish PERF_FAIL, leave #787 Draft, use measured
export/handoff/worker contributions to specify R3 versioned immutable durable
projection and mutation-generation fence. Do not read mutable service state
across multiple ticks without fencing.
