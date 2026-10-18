# FABRIC R5.6.1 R2 — WINDOWS EXACT + independent numeric RED→GREEN

Ты — Windows exact verifier на реальной машине `DESKTOP-QNAGSTI`. Выполни проверку **обновлённого R2 Numeric Conditioning Repair**, а не старого R2 R1. Не делай merge, не меняй main и product HEAD. Независимая семантическая приёмка отдельным actor нужна отдельно от implementer exact.

## Frozen identity

```text
REPO=rootfabric/distributed-world-simulator
PR=784
BRANCH=research/fabric-r5-6-1-r2-dynamic-aggregates-r1
PRODUCT_HEAD=716cddeee0cb479bcf4d96496510c0be033f5e64
PRODUCT_TREE=8457feca07484eb9d4d7f0824af8dea962e66052
RED_PARENT=2ea4debdcef7a38dc1de2a0acc9a906ccfcea442
RESEARCH_BASE=4f301fae461567362d408a51802cc3dde6730999
GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb
WINDOWS_GODOT_SHA256=3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

## Fresh worktree and exact runner (PowerShell 7.x)

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'C:\distributed-world-simulator'
$Head = '716cddeee0cb479bcf4d96496510c0be033f5e64'
$Tree = '8457feca07484eb9d4d7f0824af8dea962e66052'
$Branch = 'research/fabric-r5-6-1-r2-dynamic-aggregates-r1'
$Work = 'C:\distributed-world-simulator\work\r56-r2-numeric-win-exact-716cddee'
$Evidence = 'C:\distributed-world-simulator\evidence\r56-r2-numeric-exact-716cddee'
$GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'

git -C $Repo fetch origin --prune
$RemoteOutput = git -C $Repo ls-remote origin "refs/heads/$Branch"
if ($LASTEXITCODE -ne 0 -or !$RemoteOutput) { throw 'REMOTE_QUERY_FAILED' }
$Remote = ($RemoteOutput -split "`t")[0]
if ($Remote -ne $Head) { throw 'REMOTE_HEAD_DRIFT' }
if (Test-Path $Work) { throw 'WORKTREE_ALREADY_EXISTS' }
if ((Test-Path $Evidence) -and @(Get-ChildItem $Evidence -Force).Count -gt 0) { throw 'EVIDENCE_DIR_NOT_EMPTY' }
git -C $Repo worktree add --detach $Work $Head
if ((git -C $Work rev-parse HEAD).Trim() -ne $Head) { throw 'HEAD_MISMATCH' }
if ((git -C $Work rev-parse 'HEAD^{tree}').Trim() -ne $Tree) { throw 'TREE_MISMATCH' }
if ((Get-FileHash $GodotBin -Algorithm SHA256).Hash.ToLowerInvariant() -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') { throw 'GODOT_SHA_MISMATCH' }
& $GodotBin --version
git -C $Work diff --check 2ea4debdcef7a38dc1de2a0acc9a906ccfcea442 HEAD
Set-Location $Work
& .\RUN_FABRIC_R5_6_1_R2_TESTS.ps1 -GodotBin $GodotBin -ExpectedHead $Head -ExpectedTree $Tree -EvidenceDir $Evidence -PythonBin 'python'
if ($LASTEXITCODE -ne 0) { throw 'R56_R2_WINDOWS_EXACT_FAILED' }
```

Проверь ровно 8 изменённых файлов narrow repair против RED parent, ни одного закрытого kernel/Construction/Matter. Никакой force-push. Godot cold imports не запускать одновременно в том же worktree; не убивать чужие процессы.

## Required gates

- Cold import и parse для R2, scale, **numeric**, R1, R1 narrow: PASS.
- R2 acceptance: **3 × 626/0**, raw payload byte-identical.
- 5k / 20k / 100k scale: **255/0**.
- **Numeric conditioning: 54/0**, `stable_offsets=[1,100000,10000000,100000000,1000000000]`, `sparse_update_ok=true`, `unsafe_ranges_rejected=1`.
- R1 **203/0**, R1 Narrow **26/0**, BRIDGE-4 **49/0**.
- Exact schema `fabric.r56_r2.dynamic_aggregates.exact_evidence.v2`; strict collector PASS; tamper matrix **11/11** rejected.
- Deterministic R2 payload hash `7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43` MATCH.
- Check identity-before and identity-after byte-equal and all SHA256SUMS files validated.

## Independent original RED→GREEN falsifier

Original executable test is in separate branch:
`review/fabric-r56-r2-numeric-cancellation-falsifier-r1` at
`tests/research/fabric_bake0/review_r56_r2_large_offset_inertia_falsifier.gd`.

Replay on **separate detached worktrees**: old R2 R1 parent `2ea4debd…` must give **RED**: x=10^8 and x=10^9 produce Iyy=0 when expected 0.5 (two rejected assertions). New R2 repair `716cddee…` must give **GREEN**: full valid Iyy=0.5 for all five offsets. Keep the falsifier byte-identical; do not change its assertions. Preserve two separate raw logs and commit identities. Use `git show origin/review/fabric-r56-r2-numeric-cancellation-falsifier-r1:tests/research/fabric_bake0/review_r56_r2_large_offset_inertia_falsifier.gd` to obtain the script without changing tracked product files.

Reviewer independently challenge numeric failure envelope: find new finite inputs producing non-PSD or wrong tensor, or disprove correctness of sparse relocation and rollback. Do not assert that the heuristic is a rigorous error theorem. On any RED, save independent reproducer and return `REPAIR_REQUIRED`, no product edits during verification.

## Evidence and outcome

Create durable ZIP with raw logs, identity, SHA256SUMS, RED/GREEN source/logs and your written report. Record complete ZIP SHA256 and paths, publish GitHub PR #784 comment. Report `WINDOWS_EXACT_PASS` only if every required gate passed. For final acceptance use **separate fresh Reviewer and Verifier actors** on frozen HEAD/TREE; implementer self-validation is not independent closure. PR remains DRAFT, no merge into research/main without explicit permission.
