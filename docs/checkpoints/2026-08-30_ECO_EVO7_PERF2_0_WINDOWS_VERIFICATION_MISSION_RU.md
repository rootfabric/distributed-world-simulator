# ECO.EVO7 PERF2.0 R1 — Exact Windows Verification Mission

Цель: проверить frozen tip ветки:

```text
feature/eco-evo7-perf2-0-measurement-contract-r1
```

Predecessor:

```text
accepted STREAM1 control tip
843f503e2ff2bf4c8e38a8707380dae17088aff8

verified STREAM1 runtime/evidence subject
4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4
tree 68389ef9a491fc2f1e13efb92058029c9536f870
```

PERF2.0 is not accepted until this mission is green on exact Windows double-Godot.

## 1. Fresh detached worktree

Resolve the current remote tip; do not hard-code an older implementation SHA:

```powershell
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'feature/eco-evo7-perf2-0-measurement-contract-r1'
$Verify = 'C:\distributed-world-simulator\eco-perf2-0-r1-verify'

Set-Location $Repo
git fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

$Target = (git rev-parse "origin/$Branch").Trim()
if (Test-Path $Verify) { throw "Verification worktree already exists: $Verify" }

git worktree add --detach $Verify $Target
if ($LASTEXITCODE -ne 0) { throw 'worktree add failed' }

Set-Location $Verify
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()

Write-Host "TARGET=$Target"
Write-Host "HEAD=$Head"
Write-Host "TREE=$Tree"

if ($Head -ne $Target) { throw 'exact HEAD mismatch' }
```

## 2. Exact Godot

```powershell
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $Godot --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) { throw "Wrong Godot: $Actual" }
Write-Host "GODOT=$Actual"
```

## 3. Import

```powershell
& $Godot --headless --editor --quit --path .
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
```

Known legacy ECO5 scene parse warnings may be classified as pre-existing only if they are
byte-unchanged from accepted STREAM1 and do not change import exit code.

## 4. Canonical PERF2.0 workflow

Preferred repository-local entrypoint:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.0 -GodotPath $Godot
if ($LASTEXITCODE -ne 0) { throw "PERF2.0 workflow failed: $LASTEXITCODE" }
```

Equivalent direct runner:

```powershell
.\RUN_ECO_EVO7_PERF2_0_TESTS.ps1 -GodotPath $Godot
```

The runner must execute in this order:

```text
PERF1
STREAM1
PERF2.0
```

Expected final marker:

```text
ECO.EVO7 PERF2.0 transitive measurement-contract acceptance: PASS
```

## 5. Focused PERF2.0 expectations

Expected focused marker:

```text
ECO.EVO7 PERF2.0 Measurement Contract: PASS
```

It must prove at minimum:

- contract JSON validation;
- exact workload hash;
- serial↔STREAM1 simulation workload equivalence key;
- same-mode and cross-mode comparison fences;
- canonical result mismatch rejection;
- failed-run exclusion;
- >=3 repetition rule;
- deterministic p50/p95 summary;
- OS/static-memory probe;
- one real STREAM1 generation canonical parity with serial Workbench;
- existing PERF1 and STREAM1 timing/working-set telemetry availability;
- no PERF2 authority in Workbench/ecology source.

## 6. Final identity

```powershell
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()
$Status = @(git status --porcelain)

if ($FinalHead -ne $Target) { throw 'HEAD moved during verification' }
if ($FinalTree -ne $Tree) { throw 'TREE changed during verification' }

Write-Host "FINAL_HEAD=$FinalHead"
Write-Host "FINAL_TREE=$FinalTree"

if ($Status.Count -ne 0) {
    $Status | ForEach-Object { Write-Host $_ }
    throw 'tracked verification worktree is not clean'
}
```

Ignored logs under `artifacts/perf2_gate_logs/` are allowed.

## PASS report

Return:

```text
ECO.EVO7 PERF2.0 R1 — WINDOWS VERIFICATION

TARGET:
HEAD:
TREE:
PARENT:
Godot:

import: PASS
PERF1 regression: PASS
STREAM1 regression: PASS
PERF2.0 focused: PASS
transitive marker: PASS
worktree clean: YES

PERF2.0 assertions:
STREAM1 exact comparisons: 108/108

VERDICT: PASS
RECOMMENDATION: PERF2.0 R1 may be marked ACCEPTED; PERF2.1 may start
```

On any Parse Error, assertion failure, source guard failure or nonzero exit:

```text
VERDICT: FAIL / NEEDS_REPAIR
```

Do not repair inside the verification worktree.
