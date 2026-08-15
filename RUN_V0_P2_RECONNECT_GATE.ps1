[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = "",
    [switch]$SkipP2Preflight
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p2-live-shared-state"
$GateLog = Join-Path $ArtifactRoot "live-shared-state.log"

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot"))) { throw "Godot project file not found: $ProjectRoot" }

$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $Head -notmatch '^[0-9a-f]{40}$') { throw "Could not determine exact V0-P2 candidate HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $NormalizedExpected = $ExpectedHead.Trim().ToLowerInvariant()
    if ($Head -ne $NormalizedExpected) { throw "Wrong V0-P2 candidate HEAD. Expected $NormalizedExpected, actual $Head" }
}
if (git -C $ProjectRoot status --porcelain) { throw "V0-P2 shared-state gate requires a clean checkout." }

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Write-Host "[V0-P2 shared-state] Project: $ProjectRoot"
Write-Host "[V0-P2 shared-state] HEAD:    $Head"
Write-Host "[V0-P2 shared-state] Godot:   $GodotExe"

$HadBreakpointRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$GateExit = -1
try {
    # Disable the diagnostic MCP bridge for the complete headless validation
    # boundary, including nested P1/P2 preflight Godot processes. This makes the
    # gate safe to run while the graphical MVP owns the canonical bridge port.
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    if (-not $SkipP2Preflight) {
        Write-Host ""
        Write-Host "=== V0-P2 automated preflight ===" -ForegroundColor Cyan
        & (Join-Path $ProjectRoot "RUN_V0_P2_TESTS.ps1") -GodotExe $GodotExe -ExpectedHead $Head
        if ($LASTEXITCODE -ne 0) { throw "V0-P2 automated preflight failed before live shared-state gate." }
        if (git -C $ProjectRoot status --porcelain) { throw "V0-P2 automated preflight changed tracked checkout state." }
    }

    Write-Host ""
    Write-Host "=== V0-P2 live shared-state convergence ===" -ForegroundColor Cyan
    & $GodotExe `
        --headless `
        --path $ProjectRoot `
        --log-file $GateLog `
        --script res://tests/runtime/test_v0_p2_live_shared_state_convergence.gd
    $GateExit = $LASTEXITCODE
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

if ($GateExit -ne 0) {
    Get-Content $GateLog -Tail 300 -ErrorAction SilentlyContinue
    throw "V0-P2 live shared-state convergence failed (exit $GateExit)."
}

$FatalPatterns = @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script", "could not listen on 127.0.0.1:9081")
foreach ($Pattern in $FatalPatterns) {
    if (Select-String -Path $GateLog -SimpleMatch $Pattern -Quiet) {
        Get-Content $GateLog -Tail 300 -ErrorAction SilentlyContinue
        throw "V0-P2 shared-state log contains fatal/isolation marker: $Pattern"
    }
}

$Summary = Select-String -Path $GateLog -Pattern 'V0-P2 live shared state convergence: ([0-9]+) assertions, 0 failures' | Select-Object -Last 1
if ($null -eq $Summary) {
    Get-Content $GateLog -Tail 300 -ErrorAction SilentlyContinue
    throw "V0-P2 live gate exited zero but did not emit trusted zero-failure summary."
}
if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P2 live gate changed tracked checkout state."
}

Write-Host ""
Write-Host $Summary.Line -ForegroundColor Green
Write-Host "[V0-P2 shared-state] EXACT HEAD GREEN: $Head" -ForegroundColor Green
