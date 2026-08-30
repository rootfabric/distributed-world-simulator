# ECO.EVO7 PERF2.1 R1 — Exact Windows Verification Mission

Статус: verifier mission для frozen candidate
`feature/eco-evo7-perf2-1-stream1-generation-profiling-r1`.

## Frozen anchors

```text
PERF2.0 accepted HEAD:
5994598d317a55ddae2954f943021878a279afc9

PERF2.0 accepted TREE:
a0241f89b6fd7546a27e4388992ffe371b4c5de6

acceptance control base:
73317ce3c35a70a9f8e882e733f23539761027a8

PERF2.1 profiler runtime:
e1690106764cbcff536d939e87f1f65e9111937e

PERF2.1 acceptance harness:
9590ac289c8664a7857cebcecca5d5819450033e

PERF2.0 contract revision:
ECO.EVO7-PERF2.0-R1

PERF2.0 contract Git blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## 1. Fresh detached worktree

```powershell
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'feature/eco-evo7-perf2-1-stream1-generation-profiling-r1'
$Verify = 'C:\distributed-world-simulator\eco-perf2-1-r1-verify'

Set-Location $Repo
git fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'fetch failed' }

$Target = (git rev-parse "origin/$Branch").Trim()
if (Test-Path $Verify) { throw "worktree already exists: $Verify" }

git worktree add --detach $Verify $Target
if ($LASTEXITCODE -ne 0) { throw 'worktree creation failed' }

Set-Location $Verify
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()

if ($Head -ne $Target) { throw 'exact HEAD mismatch' }

git merge-base --is-ancestor e1690106764cbcff536d939e87f1f65e9111937e HEAD
if ($LASTEXITCODE -ne 0) { throw 'runtime anchor mismatch' }

git merge-base --is-ancestor 9590ac289c8664a7857cebcecca5d5819450033e HEAD
if ($LASTEXITCODE -ne 0) { throw 'acceptance harness mismatch' }

Write-Host "HEAD=$Head"
Write-Host "TREE=$Tree"
```

## 2. Exact Godot

```powershell
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $Godot --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) { throw "wrong Godot: $Actual" }
Write-Host "GODOT=$Actual"
```

## 3. Frozen contract

```powershell
$Contract = 'config/ecology/eco-evo7-perf2-measurement-contract.v1.json'
$Blob = (git hash-object $Contract).Trim()
if ($Blob -ne 'b076784f6b4016a0191e937c4e6ada1fe90c783b') {
    throw "PERF2.0 contract drift: $Blob"
}
$ContractDiff = @(git diff --name-only 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- $Contract)
if ($ContractDiff.Count -ne 0) { throw 'accepted PERF2.0 contract changed' }
Write-Host "PERF2_0_CONTRACT_BLOB=$Blob"
```

## 4. Runtime-diff guard

Run these commands and require no output:

```powershell
git diff --name-only 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- 'scripts/ecology/shadow/**'
if ($LASTEXITCODE -ne 0) { throw 'shadow diff query failed' }

git diff --quiet 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
if ($LASTEXITCODE -ne 0) { throw 'STREAM1 runtime changed' }

git diff --quiet 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
if ($LASTEXITCODE -ne 0) { throw 'candidate biology changed' }

git diff --quiet 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd
if ($LASTEXITCODE -ne 0) { throw 'route biology changed' }

git diff --quiet 73317ce3c35a70a9f8e882e733f23539761027a8..HEAD -- scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd
if ($LASTEXITCODE -ne 0) { throw 'recruitment biology changed' }
```

The first command must print no changed shadow files.

## 5. Import

```powershell
& $Godot --headless --editor --quit --path .
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
```

## 6. Canonical one-command gate

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.1 -GodotPath $Godot
$WorkflowExit = $LASTEXITCODE
Write-Host "WORKFLOW_EXIT=$WorkflowExit"
if ($WorkflowExit -ne 0) { throw "PERF2.1 workflow failed: $WorkflowExit" }
```

Detached worktree must print:

```text
branch=<detached-head>
```

Required sequence:

```text
PERF1
STREAM1
PERF2.0
PERF2.1
```

Required markers:

```text
ECO.EVO7 PERF1 Generation Profiler: PASS
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS
ECO.EVO7 PERF2.0 Measurement Contract: PASS
PERF2.1 cross-mode exact result pairs: 3/3
ECO.EVO7 PERF2.1 STREAM1 Generation Profiling: PASS
ECO.EVO7 PERF2.1 transitive generation-profiling acceptance: PASS
ECO WORKFLOW STAGE perf2.1: PASS
ECO repository-local test workflow: PASS
```

The PERF2.1 log must contain 12 `PERF2.1 PROFILE` rows:
2 modes × 6 metrics, each with count=3 and p50/p95/mean.

## 7. Artifact

Expected:

```text
artifacts\perf2\perf2-1-generation-profile-focused.json
```

Validate:

```powershell
$ReportPath = 'artifacts\perf2\perf2-1-generation-profile-focused.json'
if (-not (Test-Path $ReportPath -PathType Leaf)) { throw 'PERF2.1 report missing' }

$Report = Get-Content $ReportPath -Raw | ConvertFrom-Json

if ($Report.schema -ne 'distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v1') { throw 'schema mismatch' }
if ($Report.revision -ne 'ECO.EVO7-PERF2.1-R1') { throw 'revision mismatch' }
if ($Report.accepted_measurement_contract_blob_sha -ne 'b076784f6b4016a0191e937c4e6ada1fe90c783b') { throw 'contract binding mismatch' }
if ($Report.target.head -ne $Head) { throw 'report HEAD mismatch' }
if ($Report.target.tree -ne $Tree) { throw 'report TREE mismatch' }

$SampleCount = @($Report.samples).Count
$SummaryCount = @($Report.summaries).Count
if ($SampleCount -ne 6) { throw "expected 6 samples, got $SampleCount" }
if ($SummaryCount -ne 12) { throw "expected 12 summaries, got $SummaryCount" }

$Failed = @($Report.samples | Where-Object { -not $_.passed })
if ($Failed.Count -ne 0) { throw 'failed sample included' }

$BadSummary = @($Report.summaries | Where-Object { [int]$_.count -ne 3 })
if ($BadSummary.Count -ne 0) { throw 'summary repetition count mismatch' }

Write-Host "PERF2_1_REPORT_SAMPLES=$SampleCount"
Write-Host "PERF2_1_REPORT_SUMMARIES=$SummaryCount"
Write-Host "PERF2_1_REPORT_HASH=$($Report.report_hash)"
```

## 8. Final identity

```powershell
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()

if ($FinalHead -ne $Head) { throw 'HEAD changed during verification' }
if ($FinalTree -ne $Tree) { throw 'TREE changed during verification' }

$Tracked = @(git status --porcelain --untracked-files=no)
if ($Tracked.Count -ne 0) {
    $Tracked | ForEach-Object { Write-Host $_ }
    throw 'tracked worktree dirty'
}

Write-Host "FINAL_HEAD=$FinalHead"
Write-Host "FINAL_TREE=$FinalTree"
Write-Host 'TRACKED_WORKTREE_CLEAN=YES'
```

## PASS report

```text
ECO.EVO7 PERF2.1 R1 — WINDOWS VERIFICATION

TARGET:
feature/eco-evo7-perf2-1-stream1-generation-profiling-r1

HEAD:
...

TREE:
...

BASE CONTROL:
73317ce3c35a70a9f8e882e733f23539761027a8

PERF2.0 CONTRACT BLOB:
b076784f6b4016a0191e937c4e6ada1fe90c783b

Godot:
4.7.1.stable.double.custom_build.a13da4feb

fresh detached worktree: PASS
import: PASS
runtime-diff guard: PASS
PERF1: PASS
STREAM1: PASS
STREAM1 exact: 108/108
PERF2.0: PASS
PERF2.1: PASS
cross-mode exact pairs: 3/3
profile samples: 6
profile summaries: 12
artifact validation: PASS
transitive marker: PASS
canonical workflow: PASS
final identity unchanged: PASS
tracked worktree clean: YES
workflow exit: 0

VERDICT: PASS
RECOMMENDATION: PERF2.1 R1 may be marked ACCEPTED; PERF2.2 may start
```

At first failure preserve evidence and repair separately. Do not edit the
verification worktree.
