# ECO.EVO7 STREAM1 R1 — fresh Windows verification mission

Цель: проверить **текущий tip** ветки

```text
feature/eco-evo7-stream1-bounded-generation-stream-r1
```

без локальных исправлений и без подмены target SHA.

Известные immutable anchors до metadata freeze:

```text
PAR3 R3.2 predecessor:
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

STREAM1 runtime code:
8636a525c47b524e0ef597e46f37ffe6204d27ee

STREAM1 verification harness:
e0d2cda22a431c69a1b3eb4c650d79627d8aea40
```

Final verification HEAD определяется через origin/branch в момент fresh
checkout: metadata commit после этих anchors не меняет runtime code, но должен
входить в проверяемое дерево.

## 1. Fresh detached worktree

PowerShell:

```powershell
$Branch = 'feature/eco-evo7-stream1-bounded-generation-stream-r1'
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Verify = 'C:\distributed-world-simulator\eco-stream1-r1-verify'

Set-Location $Repo
git fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

$Target = (git rev-parse "origin/$Branch").Trim()
if ([string]::IsNullOrWhiteSpace($Target)) { throw 'Cannot resolve STREAM1 target HEAD' }

if (Test-Path $Verify) {
    throw "Verification path already exists: $Verify. Use a genuinely fresh worktree."
}

git worktree add --detach $Verify $Target
if ($LASTEXITCODE -ne 0) { throw 'git worktree add failed' }

Set-Location $Verify
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
$Parent = (git rev-parse 'HEAD^').Trim()

Write-Host "TARGET=$Target"
Write-Host "HEAD=$Head"
Write-Host "TREE=$Tree"
Write-Host "PARENT=$Parent"

if ($Head -ne $Target) { throw "HEAD mismatch: $Head != $Target" }
```

Не переключать ветку и не cherry-pick'ать исправления в verification worktree.

## 2. Exact Godot + import

```powershell
$env:GODOT_BIN = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$ExpectedGodot = '4.7.1.stable.double.custom_build.a13da4feb'

$ActualGodot = (& $env:GODOT_BIN --version | Select-Object -First 1).Trim()
Write-Host "GODOT=$ActualGodot"
if ($ActualGodot -ne $ExpectedGodot) {
    throw "Wrong Godot build: $ActualGodot"
}

& $env:GODOT_BIN --headless --editor --quit --path .
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
```

## 3. Source identity guards

```powershell
$CandidateKernel = 'scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd'
$RouteKernel = 'scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd'
$RecruitmentKernel = 'scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd'
$LS33 = 'scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd'
$LS34 = 'scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd'
$LS36 = 'scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd'

$ReproduceKernel = @(Select-String -Path $CandidateKernel -SimpleMatch 'LineageExtension.reproduce_bundle(').Count
$ReproduceLS33 = @(Select-String -Path $LS33 -SimpleMatch 'LineageExtension.reproduce_bundle(').Count
$RouteFormulaKernel = @(Select-String -Path $RouteKernel -SimpleMatch 'var distance_m := inherited_distance').Count
$RouteFormulaLS33 = @(Select-String -Path $LS33 -SimpleMatch 'var distance_m := inherited_distance').Count
$RecruitHashKernel = @(Select-String -Path $RecruitmentKernel -SimpleMatch 'static func recruitment_event_hash(').Count
$RecruitHashLS33 = @(Select-String -Path $LS33 -SimpleMatch 'func _recruitment_event_hash(').Count
$Facade33 = @(Select-String -Path $LS33 -SimpleMatch 'func set_generation_stream_executor(').Count
$Facade34 = @(Select-String -Path $LS34 -SimpleMatch 'func set_generation_stream_executor(').Count
$Facade36 = @(Select-String -Path $LS36 -SimpleMatch 'func set_generation_stream_executor(').Count

Write-Host "reproduce kernel=$ReproduceKernel ls33=$ReproduceLS33"
Write-Host "route formula kernel=$RouteFormulaKernel ls33=$RouteFormulaLS33"
Write-Host "recruit hash kernel=$RecruitHashKernel ls33=$RecruitHashLS33"
Write-Host "stream facades ls33=$Facade33 ls34=$Facade34 ls36=$Facade36"

if ($ReproduceKernel -ne 1 -or $ReproduceLS33 -ne 0) { throw 'Candidate single-kernel guard failed' }
if ($RouteFormulaKernel -ne 1 -or $RouteFormulaLS33 -ne 0) { throw 'Route single-kernel guard failed' }
if ($RecruitHashKernel -ne 1 -or $RecruitHashLS33 -ne 0) { throw 'Recruitment hash single-kernel guard failed' }
if ($Facade33 -ne 1 -or $Facade34 -ne 1 -or $Facade36 -ne 1) { throw 'STREAM1 public facade guard failed' }
```

## 4. Focused STREAM1 acceptance

```powershell
$FocusedLog = 'artifacts\stream1-focused-engine.log'
New-Item -ItemType Directory -Force -Path 'artifacts' | Out-Null

& $env:GODOT_BIN --headless --path . --log-file $FocusedLog --script 'res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd'

$FocusedExit = $LASTEXITCODE
Write-Host "STREAM1_FOCUSED_EXIT=$FocusedExit"
Write-Host "STREAM1_FOCUSED_LOG=$FocusedLog"
if ($FocusedExit -ne 0) { throw "STREAM1 focused acceptance failed: $FocusedExit" }
```

В stdout должны присутствовать:

```text
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS
```

Acceptance включает:

- chunk sizes 1 / 7 / 64;
- 3 physical environment recipes;
- 12 generations;
- 108 exact canonical comparisons;
- audit gen1 + gen10;
- forced chunk failure;
- forced audit mismatch;
- stale-base rejection;
- forged current-parent binding rejection;
- malformed hereditary bundle rejection;
- corrupted proposal hash rejection;
- no state mutation on failed proposal;
- public Workbench → LS3.4 → LS3.3 path.

## 5. Full transitive gate

```powershell
.\RUN_ECO_EVO7_STREAM1_TESTS.ps1 -GodotBin $env:GODOT_BIN
$FullExit = $LASTEXITCODE
Write-Host "STREAM1_FULL_EXIT=$FullExit"
if ($FullExit -ne 0) { throw "STREAM1 full gate failed: $FullExit" }
```

Финальный marker:

```text
ECO.EVO7 STREAM1 transitive acceptance: PASS
```

Per-test engine logs сохраняются в:

```text
artifacts/stream1_gate_logs/
```

При FAIL ничего не чинить в verification worktree. Сохранить первый failing
test, exit code и соответствующий log.

## 6. Final immutability evidence

```powershell
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()
$Status = @(git status --porcelain)

Write-Host "FINAL_HEAD=$FinalHead"
Write-Host "FINAL_TREE=$FinalTree"

if ($FinalHead -ne $Target) {
    throw "HEAD moved during verification: $FinalHead != $Target"
}

if ($Status.Count -ne 0) {
    Write-Host 'WORKTREE STATUS:'
    $Status | ForEach-Object { Write-Host $_ }
    throw 'Verification worktree is not clean'
}

Write-Host 'WORKTREE_CLEAN=YES'
```

Если runtime генерирует только ignored artifacts, git status --porcelain
останется пустым; сами logs можно приложить как evidence отдельно.

## PASS report

Вернуть одним отчётом:

```text
ECO.EVO7 STREAM1 R1 — WINDOWS VERIFICATION

TARGET:
HEAD:
TREE:
PARENT:
Godot:

import: PASS
source guards: PASS
focused STREAM1: PASS
exact comparisons: 108/108
transitive gate: PASS
worktree clean: YES

VERDICT: PASS
```

При любом отклонении итоговый verdict только **FAIL / NEEDS_REPAIR**, с первым
точным failure и сохранённым evidence.
