[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = "",
    [switch]$SkipP1Preflight
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p1-live-reconnect"
$ReconnectLog = Join-Path $ArtifactRoot "live-reconnect.log"

if (-not (Test-Path -LiteralPath $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot"))) {
    throw "Godot project file not found: $ProjectRoot"
}

$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $Head -notmatch '^[0-9a-f]{40}$') {
    throw "Could not determine exact V0-P1 reconnect candidate HEAD."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $NormalizedExpected = $ExpectedHead.Trim().ToLowerInvariant()
    if ($Head -ne $NormalizedExpected) {
        throw "Wrong reconnect candidate HEAD. Expected $NormalizedExpected, actual $Head"
    }
}
if (git -C $ProjectRoot status --porcelain) {
    throw "V0-P1 reconnect gate requires a clean checkout."
}

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Write-Host "[V0-P1 reconnect] Project: $ProjectRoot"
Write-Host "[V0-P1 reconnect] HEAD:    $Head"
Write-Host "[V0-P1 reconnect] Godot:   $GodotExe"

if (-not $SkipP1Preflight) {
    Write-Host ""
    Write-Host "=== V0-P1 existing preflight ===" -ForegroundColor Cyan
    & (Join-Path $ProjectRoot "RUN_V0_P1_TESTS.ps1") -GodotExe $GodotExe
    if ($LASTEXITCODE -ne 0) {
        throw "Existing V0-P1 preflight failed before reconnect gate."
    }
    if (git -C $ProjectRoot status --porcelain) {
        throw "Existing V0-P1 preflight changed tracked checkout state."
    }
}

Write-Host ""
Write-Host "=== V0-P1 live reconnect convergence ===" -ForegroundColor Cyan
& $GodotExe `
    --headless `
    --path $ProjectRoot `
    --log-file $ReconnectLog `
    --script res://tests/runtime/test_v0_p1_live_reconnect_convergence.gd
$ReconnectExit = $LASTEXITCODE

if ($ReconnectExit -ne 0) {
    Get-Content $ReconnectLog -Tail 240 -ErrorAction SilentlyContinue
    throw "V0-P1 live reconnect convergence failed (exit $ReconnectExit)."
}

$FatalPatterns = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "Failed to load script"
)
foreach ($Pattern in $FatalPatterns) {
    if (Select-String -Path $ReconnectLog -SimpleMatch $Pattern -Quiet) {
        Get-Content $ReconnectLog -Tail 240 -ErrorAction SilentlyContinue
        throw "Reconnect log contains fatal marker: $Pattern"
    }
}

$Summary = Select-String -Path $ReconnectLog -Pattern 'V0-P1 live reconnect convergence: ([0-9]+) assertions, 0 failures' | Select-Object -Last 1
if ($null -eq $Summary) {
    Get-Content $ReconnectLog -Tail 240 -ErrorAction SilentlyContinue
    throw "Reconnect runner exited zero but did not emit a trusted zero-failure summary."
}

if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P1 reconnect gate changed tracked checkout state."
}

Write-Host ""
Write-Host $Summary.Line -ForegroundColor Green
Write-Host "[V0-P1 reconnect] EXACT HEAD GREEN: $Head" -ForegroundColor Green
