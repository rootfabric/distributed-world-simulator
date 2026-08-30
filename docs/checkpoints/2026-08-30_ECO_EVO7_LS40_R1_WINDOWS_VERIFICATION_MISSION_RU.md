# ECO.EVO7 LS4.0 R1 — fresh exact-Windows verification mission

Цель: независимо проверить branch-local research checkpoint:

```text
feature/eco-evo7-ls40-seasonal-succession-r1
```

без repair внутри verification worktree и без подмены target.

LS4.0 **не является canonical main ECO project state**. Эта mission проверяет
только frozen ECO.EVO7 research lineage.

## Immutable implementation anchors

```text
STREAM1 acceptance control base:
5beb603ebdae2e89ad8f66f469e7ecc12312c29e

LS4.0 runtime code:
c1ad4f1c4b1d8b1c37f7279f5365588c569ac637

LS4.0 acceptance test:
4328583fd5f01f7a22304cd4d354ca54a59ac4aa

LS4.0 verification harness freeze:
c1ad4f1c4b1d8b1c37f7279f5365588c569ac637
```

Final metadata HEAD определяется через origin branch в момент fresh checkout.
Verifier обязан проверить, что оба LS4 anchors являются ancestors final target.

## 1. Fresh detached worktree

PowerShell:

```powershell
$Branch = 'feature/eco-evo7-ls40-seasonal-succession-r1'
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Verify = 'C:\distributed-world-simulator\eco-ls40-r1-verify'

Set-Location $Repo
git fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

$Target = (git rev-parse "origin/$Branch").Trim()
if ([string]::IsNullOrWhiteSpace($Target)) { throw 'Cannot resolve LS4.0 target' }

if (Test-Path $Verify) {
    throw "Verification path already exists: $Verify. Use a genuinely fresh worktree."
}

git worktree add --detach $Verify $Target
if ($LASTEXITCODE -ne 0) { throw 'git worktree add failed' }

Set-Location $Verify

$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()

Write-Host "TARGET=$Target"
Write-Host "HEAD=$Head"
Write-Host "TREE=$Tree"

if ($Head -ne $Target) { throw "HEAD mismatch: $Head != $Target" }

git merge-base --is-ancestor c1ad4f1c4b1d8b1c37f7279f5365588c569ac637 HEAD
if ($LASTEXITCODE -ne 0) { throw 'LS4 runtime anchor is not an ancestor of target' }

git merge-base --is-ancestor 4328583fd5f01f7a22304cd4d354ca54a59ac4aa HEAD
if ($LASTEXITCODE -ne 0) { throw 'LS4 acceptance-test anchor is not an ancestor of target' }

git merge-base --is-ancestor c1ad4f1c4b1d8b1c37f7279f5365588c569ac637 HEAD
if ($LASTEXITCODE -ne 0) { throw 'LS4 verification harness freeze is not an ancestor of target' }
```

Ничего не cherry-pick'ать и не исправлять в verification worktree.

## 2. Exact Godot

```powershell
$env:GODOT_BIN = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$ExpectedGodot = '4.7.1.stable.double.custom_build.a13da4feb'

$ActualGodot = (& $env:GODOT_BIN --version | Select-Object -First 1).Trim()
Write-Host "GODOT=$ActualGodot"

if ($ActualGodot -ne $ExpectedGodot) {
    throw "Wrong Godot build: $ActualGodot"
}
```

Любая другая версия = **FAIL**.

## 3. Fresh import

```powershell
New-Item -ItemType Directory -Force -Path 'artifacts' | Out-Null
$ImportLog = 'artifacts\ls40-import.log'

& $env:GODOT_BIN --headless --editor --quit --path . --log-file $ImportLog
$ImportExit = $LASTEXITCODE

Write-Host "IMPORT_EXIT=$ImportExit"
Write-Host "IMPORT_LOG=$ImportLog"

if ($ImportExit -ne 0) {
    throw "Godot import failed: $ImportExit"
}
```

Из предыдущих accepted Windows runs известны legacy diagnostics
`Expected '['` в старых ECO.EVO5 scene-файлах. Они сами по себе не являются
LS4 regression при exit 0.

Legacy Parse Error в import log сохранить как baseline evidence. Новые LS4
scripts окончательно проверяются focused запуском ниже: focused log не должен
содержать ни одного `Parse Error`, а exit code обязан быть 0.

## 4. Source guards

```powershell
$LS40 = 'scripts/ecology/shadow/eco_evo7_ls40_seasonal_forcing_v1.gd'
$LS33 = 'scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd'
$LS34 = 'scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd'
$LS36 = 'scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd'
$Obs  = 'scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd'

if (@(Select-String -Path $LS40 -SimpleMatch '.step_generation(').Count -ne 0) {
    throw 'LS4 forcing must not advance ecology'
}
if (@(Select-String -Path $LS40 -SimpleMatch 'reproduce_bundle(').Count -ne 0) {
    throw 'LS4 forcing must not own reproduction'
}
if (@(Select-String -Path $LS33 -SimpleMatch 'func set_environment_field(').Count -ne 1) {
    throw 'LS3.3 environment seam count mismatch'
}
if (@(Select-String -Path $LS34 -SimpleMatch 'func set_environment_field(').Count -ne 1) {
    throw 'LS3.4 environment seam count mismatch'
}
if (@(Select-String -Path $LS36 -SimpleMatch 'func set_environment_forcing_provider(').Count -ne 1) {
    throw 'Workbench LS4 provider seam count mismatch'
}
if (@(Select-String -Path $LS36 -SimpleMatch '.environment_for_generation(').Count -ne 1) {
    throw 'Workbench seasonal proposal call-site count mismatch'
}
if (@(Select-String -Path $Obs -SimpleMatch 'String(ecology_snapshot.get("environment_field_hash", "")) != current_environment_hash').Count -ne 1) {
    throw 'Observatory per-generation environment binding guard failed'
}

$ForbiddenLabels = @(
    'desert-like',
    'wetland-like',
    'forest-like',
    'grass/shrub-like',
    'alpine-like',
    'ecotone'
)
$LS40Lower = (Get-Content $LS40 -Raw).ToLowerInvariant()
foreach ($Label in $ForbiddenLabels) {
    if ($LS40Lower.Contains($Label)) {
        throw "LS4 forcing illegally depends on post-hoc biome label: $Label"
    }
}
if ($LS40Lower.Contains('fileaccess') -or $LS40Lower.Contains('diraccess') -or $LS40Lower.Contains('multiplayer')) {
    throw 'LS4 forcing owns forbidden persistence/network path'
}

$LS33Text = Get-Content $LS33 -Raw
$SetterMatch = [regex]::Match(
    $LS33Text,
    '(?ms)^func set_environment_field\(.*?(?=^func )'
)
if (-not $SetterMatch.Success) {
    throw 'Cannot isolate LS3.3 environment setter'
}
$SetterBody = $SetterMatch.Value
if ($SetterBody.Contains('generation =') -or $SetterBody.Contains('records =')) {
    throw 'LS3.3 environment setter contains generation/population mutation'
}
if (-not $SetterBody.Contains('STATIC_ENVIRONMENT_CELL_FIELDS')) {
    throw 'LS3.3 environment setter lost static physical identity fence'
}

Write-Host 'LS4_SOURCE_GUARDS=PASS'
```

## 5. Focused LS4 acceptance

```powershell
$FocusedLog = 'artifacts\ls40-focused.log'

& $env:GODOT_BIN --headless --path . --log-file $FocusedLog --script 'res://tests/ecology/eco_evo7_ls40_seasonal_succession_acceptance.gd'

$FocusedExit = $LASTEXITCODE
Write-Host "LS40_FOCUSED_EXIT=$FocusedExit"
Write-Host "LS40_FOCUSED_LOG=$FocusedLog"

if ($FocusedExit -ne 0) {
    throw "LS4.0 focused acceptance failed: $FocusedExit"
}
if (Select-String -Path $FocusedLog -SimpleMatch 'Parse Error' -Quiet) {
    throw 'LS4.0 focused log contains Parse Error'
}
```

Обязательные markers:

```text
LS4.0 STREAM1 seasonal exact comparisons: 6/6
ECO.EVO7 LS4.0 Seasonal Forcing / Succession: PASS
```

Focused acceptance должен подтвердить:

- STATIC_CONTROL exact legacy parity;
- 12 forcing phases;
- generation 13 == generation 1;
- LS3.1-compatible derived hashes;
- frozen terrain/substrate identity;
- same-founder seasonal counterfactual;
- deterministic seasonal replay;
- causal recruitment/competition/population/heredity divergence;
- STREAM1 exact seasonal 6/6;
- malformed field fail-closed;
- rehashed static terrain tamper rejection;
- environment setter cannot advance generation or mutate population/heredity.

## 6. Full LS4 transitive gate

```powershell
.\RUN_ECO_EVO7_LS40_TESTS.ps1 -GodotBin $env:GODOT_BIN
$FullExit = $LASTEXITCODE

Write-Host "LS40_FULL_EXIT=$FullExit"

if ($FullExit -ne 0) {
    throw "LS4.0 full gate failed: $FullExit"
}
```

Runner обязан пройти **14/14 suites**:

```text
LS3.3
LS3.4
LS3.5
LS3.6
PERF1
PAR0
PAR0.2
PAR1
PAR2
PAR3
STREAM1
LS4.0
VIS3
PLAY0
```

Финальный marker:

```text
ECO.EVO7 LS4.0 transitive acceptance: PASS
```

Per-test logs:

```text
artifacts\ls40_gate_logs\
```

## 7. Final immutable identity

После всех тестов:

```powershell
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()

Write-Host "FINAL_HEAD=$FinalHead"
Write-Host "FINAL_TREE=$FinalTree"

if ($FinalHead -ne $Target) {
    throw "HEAD moved during verification: $FinalHead != $Target"
}

git diff --quiet
if ($LASTEXITCODE -ne 0) {
    throw 'Tracked working tree changed during verification'
}

git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    throw 'Index changed during verification'
}

Write-Host 'TRACKED_WORKTREE_CLEAN=YES'
git status --short
```

Untracked Godot `.uid` sidecars и test logs перечислить в evidence, но они не
являются source mutation. Никаких tracked изменений быть не должно.

## 8. PASS criteria

LS4.0 R1 можно рекомендовать к acceptance только если одновременно:

```text
fresh detached target             PASS
runtime anchor ancestor           PASS
verification harness ancestor     PASS
exact Godot                       PASS
import exit 0                     PASS
focused log parse-clean           PASS
source guards                     PASS
focused LS4                       PASS
STREAM1 seasonal parity           6/6
transitive gate                   14/14 PASS
final HEAD/TREE unchanged         PASS
tracked worktree clean            YES
```

При любом отклонении:

```text
VERDICT: FAIL
RECOMMENDATION: preserve R1 evidence and repair on a separate revision
```

Не чинить R1 внутри verification worktree.

## PASS report

Вернуть:

```text
ECO.EVO7 LS4.0 R1 — WINDOWS VERIFICATION

TARGET:
feature/eco-evo7-ls40-seasonal-succession-r1

HEAD:
...

TREE:
...

BASE:
5beb603ebdae2e89ad8f66f469e7ecc12312c29e

RUNTIME ANCHOR:
c1ad4f1c4b1d8b1c37f7279f5365588c569ac637

ACCEPTANCE TEST ANCHOR:
4328583fd5f01f7a22304cd4d354ca54a59ac4aa

VERIFICATION HARNESS FREEZE:
c1ad4f1c4b1d8b1c37f7279f5365588c569ac637

Godot:
4.7.1.stable.double.custom_build.a13da4feb

fresh detached worktree: PASS
import: PASS
source guards: PASS
focused LS4.0: PASS
STREAM1 seasonal exact: 6/6
transitive gate: 14/14 PASS
final identity unchanged: PASS
tracked worktree clean: YES

VERDICT: PASS
RECOMMENDATION: LS4.0 R1 may be proposed for independent acceptance
```

Не писать `ACCEPTED` самостоятельно: verifier предоставляет evidence, а
formal acceptance фиксируется отдельным control/review checkpoint.
