[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = "",
    [switch]$SkipP1Preflight
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p2-first-slice"

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "Godot project file not found: $ProjectFile" }
$ActualHead = (& git -C $ProjectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ActualHead)) { throw "Unable to resolve repository HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $ActualHead -ne $ExpectedHead) { throw "V0-P2 exact-head mismatch. Expected $ExpectedHead, got $ActualHead" }

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$ProjectHashBefore = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
$FatalPatterns = @("SCRIPT ERROR:", "Failed to instantiate an autoload", "Resource file not found: res://", "Failed to load script")

function Assert-ProjectStable {
    param([string]$Stage)
    $ProjectHashAfter = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
    if ($ProjectHashAfter -ne $ProjectHashBefore) {
        Write-Host "[V0-P2] project.godot changed during $Stage." -ForegroundColor Red
        & git -C $ProjectRoot diff -- project.godot
        throw "V0-P2 verification mutated tracked project.godot during $Stage."
    }
}
function Assert-LogClean {
    param([string]$LogPath, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $LogPath -SimpleMatch $Pattern -Quiet) {
            Write-Host "[V0-P2] Fatal compiler/startup error during ${Stage}:" -ForegroundColor Red
            Get-Content $LogPath -Tail 180 -ErrorAction SilentlyContinue
            throw "V0-P2 $Stage is not parser-clean. See $LogPath"
        }
    }
}
function Invoke-P2Test {
    param([string]$TestPath, [string]$LogName)
    $LogPath = Join-Path $ArtifactRoot $LogName
    Write-Host ""
    Write-Host "=== $TestPath ===" -ForegroundColor Cyan
    & $GodotExe --headless --path $ProjectRoot --log-file $LogPath --script $TestPath
    if ($LASTEXITCODE -ne 0) {
        Get-Content $LogPath -Tail 220 -ErrorAction SilentlyContinue
        throw "V0-P2 test failed: $TestPath (exit $LASTEXITCODE)"
    }
    Assert-LogClean -LogPath $LogPath -Stage $TestPath
    Assert-ProjectStable -Stage $TestPath
}

Write-Host "[V0-P2] Project: $ProjectRoot"
Write-Host "[V0-P2] HEAD:    $ActualHead"
Write-Host "[V0-P2] Godot:   $GodotExe"

if (-not $SkipP1Preflight) {
    Write-Host ""
    Write-Host "=== EXISTING V0-P1 REGRESSION ===" -ForegroundColor Cyan
    & (Join-Path $ProjectRoot "RUN_V0_P1_TESTS.ps1") -GodotExe $GodotExe
    if ($LASTEXITCODE -ne 0) { throw "Existing V0-P1 regression failed (exit $LASTEXITCODE)." }
    Assert-ProjectStable -Stage "V0-P1 regression"
}
else {
    Write-Host ""
    Write-Host "=== FOCUSED IMPORT (P1 PREFLIGHT SKIPPED) ===" -ForegroundColor Yellow
    $ImportLog = Join-Path $ArtifactRoot "focused-import.log"
    & $GodotExe --headless --editor --path $ProjectRoot --log-file $ImportLog --import
    if ($LASTEXITCODE -ne 0) {
        Get-Content $ImportLog -Tail 180 -ErrorAction SilentlyContinue
        throw "V0-P2 focused import failed. See $ImportLog"
    }
    Assert-LogClean -LogPath $ImportLog -Stage "focused import"
    Assert-ProjectStable -Stage "focused import"
}

Invoke-P2Test -TestPath "res://tests/runtime/test_v0_p2_item_graph_restore_purity.gd" -LogName "item-graph-restore-purity.log"
Invoke-P2Test -TestPath "res://tests/runtime/test_v0_p2_canonical_state_fingerprint.gd" -LogName "canonical-state-fingerprint.log"

$Status = @(& git -C $ProjectRoot status --short --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect repository cleanliness after V0-P2 verification." }
if ($Status.Count -gt 0) {
    Write-Host "[V0-P2] Checkout is not clean after verification:" -ForegroundColor Red
    $Status | ForEach-Object { Write-Host $_ }
    throw "V0-P2 verification left repository changes."
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "V0-P2 AUTOMATED GREEN" -ForegroundColor Green
Write-Host $ActualHead -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
