[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectFile = Join-Path $ProjectRoot "project.godot"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p1-preflight"

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}
if (-not (Test-Path -LiteralPath $ProjectFile)) {
    throw "Godot project file not found: $ProjectFile"
}
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

$ProjectHashBefore = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
$FatalPatterns = @(
    "SCRIPT ERROR:",
    "Failed to instantiate an autoload",
    "Resource file not found: res://",
    "Failed to load script"
)

function Assert-ProjectStable {
    param([string]$Stage)
    $ProjectHashAfter = (Get-FileHash -Path $ProjectFile -Algorithm SHA256).Hash
    if ($ProjectHashAfter -ne $ProjectHashBefore) {
        Write-Host "[V0-P1] project.godot changed during $Stage." -ForegroundColor Red
        & git -C $ProjectRoot diff -- project.godot
        throw "V0-P1 preflight mutated tracked project.godot during $Stage."
    }
}

function Assert-LogClean {
    param([string]$LogPath, [string]$Stage)
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $LogPath -SimpleMatch $Pattern -Quiet) {
            Write-Host "[V0-P1] Fatal compiler/startup error during ${Stage}:" -ForegroundColor Red
            Get-Content $LogPath -Tail 140
            throw "V0-P1 $Stage is not parser-clean. See $LogPath"
        }
    }
}

function Invoke-GodotScriptTest {
    param([string]$TestPath)
    $SafeName = ($TestPath -replace '^res://', '') -replace '[\\/:]', '_'
    $LogPath = Join-Path $ArtifactRoot "$SafeName.log"
    Write-Host ""
    Write-Host "=== $TestPath ==="
    & $GodotExe --headless --path $ProjectRoot --log-file $LogPath --script $TestPath
    if ($LASTEXITCODE -ne 0) {
        Get-Content $LogPath -Tail 160 -ErrorAction SilentlyContinue
        throw "V0-P1 test failed: $TestPath (exit $LASTEXITCODE)"
    }
    Assert-LogClean -LogPath $LogPath -Stage $TestPath
    Assert-ProjectStable -Stage $TestPath
}

Write-Host "[V0-P1] Project: $ProjectRoot"
Write-Host "[V0-P1] Godot:   $GodotExe"
Write-Host "[V0-P1] Building clean-checkout UID/script-class cache..." -ForegroundColor Cyan

$BootstrapLog = Join-Path $ArtifactRoot "bootstrap.log"
$VerifyLog = Join-Path $ArtifactRoot "verify.log"
& $GodotExe --headless --editor --path $ProjectRoot --log-file $BootstrapLog --import
if ($LASTEXITCODE -ne 0) {
    throw "V0-P1 bootstrap import failed. See $BootstrapLog"
}
Assert-LogClean -LogPath $BootstrapLog -Stage "bootstrap import"
Assert-ProjectStable -Stage "bootstrap import"

& $GodotExe --headless --editor --path $ProjectRoot --log-file $VerifyLog --import
if ($LASTEXITCODE -ne 0) {
    throw "V0-P1 verification import failed. See $VerifyLog"
}
Assert-LogClean -LogPath $VerifyLog -Stage "verification import"
Assert-ProjectStable -Stage "verification import"

$UidLog = Join-Path $ArtifactRoot "uid-contract.log"
& $GodotExe `
    --headless `
    --path $ProjectRoot `
    --log-file $UidLog `
    --script res://tests/runtime/test_int0_project_uid_contracts.gd `
    -- `
    --require-imported-uids
if ($LASTEXITCODE -ne 0) {
    Get-Content $UidLog -Tail 160 -ErrorAction SilentlyContinue
    throw "V0-P1 imported UID contract failed. See $UidLog"
}
Assert-LogClean -LogPath $UidLog -Stage "imported UID contract"
Assert-ProjectStable -Stage "imported UID contract"

$Tests = @(
    "res://tests/runtime/test_v0_p1_earth_wiring.gd",
    "res://tests/runtime/test_v0_p1_world_items_containers.gd",
    "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
    "res://tests/runtime/test_v0_s1_mvp_launch_options.gd"
)
foreach ($Test in $Tests) {
    Invoke-GodotScriptTest -TestPath $Test
}

Write-Host ""
Write-Host "[V0-P1] Clean-checkout import, UID gate, focused P1 tests, and regressions passed." -ForegroundColor Green
