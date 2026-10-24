# NET-SMOOTH1 #815 — Fresh two-client JOIN reproducibility campaign R1

## Frozen identity and isolation

Only diagnose, do not merge product. The exact tested product remains Draft PR #840 HEAD `fb513173df4c73c607fd8cb6680ad108c76f41ac`, TREE `24b04c3381aee947aeb4b61f0576b4a2c67e550d`. This standalone diagnostics/tools branch is NOT the product HEAD. Do NOT run the diagnostic branch as the product; two separate detached worktrees are mandatory.

Do not relax `PAYLOAD_CHECKSUM_MISMATCH`, process isolation, M6 ACK/replay, or original server/client p99 thresholds. The purpose is ≥10 independent fresh JOIN attempts on exactly one product HEAD, five R2.1-only (OFF) and five R2.2 (ON), with full original logs and evidence of every failure. Even ten clean attempts cannot close #815, which had earlier failures on PR #809 and PR #823.

Current Windows R2.2 repeated pair from human report: OFF p99 29.066ms / ON p99 28.043ms, 3421 vs 3417 flush packets, and 0 observed JOIN/checksum violations. This is a useful *diagnostic* signal but both arms fail the p99<=25ms release criterion, and original C:\EVIDENCE\R22_STAGE4_SUMMARY.md is local-only until published independently.

## Run on native Windows desktop with no other active NET-SMOOTH Godot

~~~powershell
$ErrorActionPreference = 'Stop'
git fetch origin
git worktree add --detach C:\dws-r22-frozen fb513173df4c73c607fd8cb6680ad108c76f41ac
git worktree add --detach C:\dws-815-tools origin/diagnostic/net-smooth1-r31-815-fresh-join-campaign-r1
$G = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Pin = '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
if ((Get-FileHash $G -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Pin) { throw 'GODOT_WRAPPER_SHA_MISMATCH' }
Get-FileHash 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe' -Algorithm SHA256
python C:\dws-815-tools\tools\net_smooth1\run_r31_issue815_join_campaign.py --product C:\dws-r22-frozen --godot $G --expected-head fb513173df4c73c607fd8cb6680ad108c76f41ac --expected-tree 24b04c3381aee947aeb4b61f0576b4a2c67e550d --expected-godot-sha256 $Pin --output C:\EVIDENCE\R31_ISSUE815_JOIN_R1 --attempts 10 --order OFF_ON
~~~

This helper performs cold import once and runs the unmodified product `tools/net_smooth1/run_net_smooth1.py` ten times in *new* server/2-client groups (real Earth, real Quaternius, LOCAL, 12s smoke movement, original optional B reconnect). It checks exact product HEAD/TREE/clean status and pinned Godot/224 Quaternius assets before each attempt; the inherited #820 Job Guard handles owned descendants. It NEVER retries or silently drops a failed fresh JOIN. A failed isolation check stops the campaign instead of launching into an unsafe process environment.

All attempts have separate `attempts/attempt-XX-{off,on}` roots, `logs/attempt-XX.stdout.log`, original manifests/reports/runtime traces and per-root SHA256 inventories. Summary `campaign.json` records each original result, exit code, raw integrity, initial real two-client connection receipts and ALL checksum occurrences. An error after initial-state receipt is not misreported as an initial JOIN error; a missing receipt with checksum is only a *candidate* premeasure issue until correlation with frame/session/sequence.

Use `python -m unittest discover -s tests/tools -p 'test_net_smooth1_r31_issue815_join_campaign.py' -v` in tools branch for local offline tests. In the clean ten-run case the campaign says `NO_INCIDENT_OBSERVED_ISSUE_815_STILL_OPEN`, which is intentionally not accepted as proof of bug elimination. It is NOT the 3x120s normative GUI test.

## Distinct release gates

1. R2.2 official Windows Exact SUCCESS; official Linux Exact still queued on the checked product HEAD, despite separate WSL 23/23 PASS reported by the Windows agent.
2. Project Control RED is candidate main drift: recorded main `3d7672cba293d8e7bd72427b803f73fc8fcee5da` vs canonical current main `aac301b9a9a89e027f6d99864437eb750a4202ca`. Requires separately reviewed candidate snapshot/reconciliation; do not rewrite main or control policy.
3. Historic P7.4 was completed and merged on 2026-08-31 (PR #396, #428, #430). Its new NET-SMOOTH1 integration/regression inheritance remains separate, as does SEAM-E2E.
4. Release performance Stage 5 must be done only on a genuinely quiet or independently isolated Windows host: three balanced 120s two-client pairs, 20s warmup, native p99<=25ms/p999<=50ms/max<=100ms, >=59Hz, no unexplained >100ms. A CPU-contended ~35% Chrome/node desktop is not acceptable as sole performance evidence. Do not change the thresholds.

**#815 OPEN / READY_FOR_MERGE=false.**
