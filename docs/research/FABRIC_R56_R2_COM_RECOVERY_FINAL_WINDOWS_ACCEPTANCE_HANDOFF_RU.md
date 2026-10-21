# FABRIC R5.6.1 R2 COM Recovery — final independent Reviewer / Verifier

**Frozen product:** `rootfabric/distributed-world-simulator`, PR #784.

- HEAD `60f193d6602d2d6ebb62393d3db6633b14623627`
- TREE `1a92363e7cc159fef4c42e3443542ebb00a71464`
- RED COM Recovery parent `91223acb7bf79c37e12fc11d44054ad3e2732455`
- Research base (merged R1) `4f301fae461567362d408a51802cc3dde6730999`
- Canonical Windows Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`
- Windows host `DESKTOP-QNAGSTI`, PowerShell 7.x. Official result hash `7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`.

## Mission

Organize **two genuinely separate fresh subagent sessions and two independent detached worktrees** at the exact frozen HEAD. A single agent re-running tests twice is not two independent approvals. Reviewer A must not read Verifier B's conclusion, and vice versa, until both have frozen their own results. There is already a Windows exact report and fresh Ubuntu reviewer-style/verifier evidence; use those as regressions, not as independent acceptance in place of these two agents.

Do not edit Product, replace tests, lower thresholds, force-push, alter main, or merge. Do not terminate other agents' services or share `.godot` import directories. Schedule cold imports nonoverlapping to avoid breakpoint_mcp port collisions.

## Preflight common to both actors

```powershell
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Head = '60f193d6602d2d6ebb62393d3db6633b14623627'
$Tree = '1a92363e7cc159fef4c42e3443542ebb00a71464'
$Branch = 'research/fabric-r5-6-1-r2-dynamic-aggregates-r1'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin --prune
$remote = git -C $Repo ls-remote origin "refs/heads/$Branch"
if ($LASTEXITCODE -ne 0 -or ($remote -split '\s+')[0] -cne $Head) { throw 'REMOTE_HEAD_DRIFT' }
if ((Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant() -cne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
```

Each actor creates their own NEW detached worktree (`work/r56-r2-reviewerA-60f193d` and `work/r56-r2-verifierB-60f193d`), verifies exact HEAD/TREE, tracked-clean, `git diff --check`, and the parent chain. Do not reuse previous implementer worktrees.

## Actor A — Independent semantic Reviewer

1. Review full path: `r5_6_1_r2_dynamic_aggregate_session_v1.gd` / `r5_6_1_r2_part_delta_contract_v1.gd` / `r5_6_1_r2_dynamic_aggregate_index_v1.gd` / Construction Store / BRIDGE-4. Follow source fencing and immutable prepare intent, external owner mutation receipt, detached capsule, stage-before-commit and every guard preceding publication. Note that Store type and instance binding are in-process trust, not remote cryptographic identity.
2. Reproduce original COM recovery liveness RED on parent `91223acb...` and GREEN on `60f193d...` using **the unchanged same script** from branch `review/fabric-r56-r2-owner-com-recovery-liveness-r2` at `tests/research/fabric_bake0/review_r56_r2_owner_com_recovery.gd`. Use `git cat-file` or `git show` byte-preserving transport. Original parent rejects the legal recovery; repaired version accepts and commits exactly twice without leaking Matter or bypassing stale fences.
3. Independently devise **at least one new falsifier** not copied from previous Ubuntu's multi-range recovery test or Windows 95-check test. Strong candidates: moving the initial reference part while another region is COM-unsafe; malformed owner source revision paired with valid mass; adversarial multi-event change from safe→unsafe→safe followed by a conflicting event; range-index graph publication mismatch. Verify numeric fail-closed, no partial commit, correct recovery and parity with an independent direct point-mass oracle.
4. Verify that fail-closed COM query never prevents a valid owner-verified update if it is a legal path back to a safe state; do not weaken the actual COM representability guard.
5. State the exact error and physical witness for every case. Distinguish `SOUND`, `CONCERN`, `DEFECT`, `BLOCKER`. Explain point-mass-only scope, lack of intrinsic inertia, O(k log N) **index only**, expensive canonical snapshots/BRIDGE-4 O(N), 1 µm COM *representation-conversion* budget rather than universal total accuracy.
6. Deliver `FABRIC_R56_R2_60F193D_FRESH_WINDOWS_REVIEWER_RU.md`, own executable falsifier, raw RED/GREEN/new logs, SHA256SUMS, and GitHub PR comment. Verdict: `REVIEWER_PASS`, `PASS_WITH_NONBLOCKING_FINDINGS`, `REVIEWER_FAIL_WITH_FALSIFIER`, or `REVIEW_BLOCKED`.

## Actor B — Independent exact Verifier

On its own fresh checkout with empty evidence directory, run the unchanged published PowerShell runner:

```powershell
$Head = '60f193d6602d2d6ebb62393d3db6633b14623627'
$Tree = '1a92363e7cc159fef4c42e3443542ebb00a71464'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Evidence = 'C:\distributed-world-simulator\evidence\r56-r2-fresh-final-verifier-60f193d'
& .\RUN_FABRIC_R5_6_1_R2_TESTS.ps1 `
    -GodotBin $GodotBin `
    -ExpectedHead $Head `
    -ExpectedTree $Tree `
    -EvidenceDir $Evidence `
    -PythonBin 'python'
if ($LASTEXITCODE -ne 0) { throw 'FRESH_WINDOWS_EXACT_FAILED' }
```

Expected immutable gates:

| Gate | Expected |
| --- | --- |
| Import / parse | PASS, 7 parse tests |
| R2 core | 3 × 626/0, byte-identical, hash `7fb3eb72…98dd43` |
| R2 scale | 255/0, 5k/20k/100k |
| Numeric conditioning | 54/0 |
| COM representability | 52/0 (6 unsafe refused, 2 safe accepted) |
| COM Recovery | 18/0; mass/stale/replay rejected; one liveness recovery |
| R1 | 203/0 |
| R1 Narrow | 26/0 |
| BRIDGE-4 | 49/0 |
| Strict collector | `fabric.r56_r2.dynamic_aggregates.exact_evidence.v4` PASS |
| Evidence tamper suite | 21/21 rejected |
| Identity and SHA256SUMS | before == after, every file rehashed |

Check cross-platform stable raw result payload and deterministic hash against fresh Linux evidence. The previous Windows 95/95 falsifier is useful historical context but is *not* the new Reviewer A falsifier. If first attempt suffers a breakpoint_mcp port conflict, archive logs and retry only with an unchanged runner and a NEW empty directory; never hide the failed attempt.

Deliver `FABRIC_R56_R2_60F193D_FRESH_WINDOWS_VERIFIER_RU.md`, raw exact evidence, SHA256 manifest and evidence ZIP checksum, and own GitHub PR comment. Verdict `VERIFIED`, `FAIL`, or `HOST_BLOCKED`.

## Final independent gate

Merge-ready requires **both** separate-actor verdicts at **the same frozen HEAD/TREE**, no blocking defects, complete exact evidence, no remote drift, and a final explicit user merge authorization. Do not merge in either actor session. If fail, publish a minimal reproducer in a separate review branch and return `REPAIR_REQUIRED` without changing product.
