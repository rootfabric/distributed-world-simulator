[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\runtime\v0-p3-live-resource-mining"
$LiveLog = Join-Path $ArtifactRoot "live-resource-mining.log"

if (-not (Test-Path -LiteralPath $GodotExe)) { throw "Godot executable not found: $GodotExe" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot"))) { throw "Godot project file not found: $ProjectRoot" }

$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $Head -notmatch '^[0-9a-f]{40}$') { throw "Could not determine exact V0-P3 candidate HEAD." }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $NormalizedExpected = $ExpectedHead.Trim().ToLowerInvariant()
    if ($Head -ne $NormalizedExpected) { throw "Wrong V0-P3 candidate HEAD. Expected $NormalizedExpected, actual $Head" }
}
if (git -C $ProjectRoot status --porcelain) { throw "V0-P3 resource-mining gate requires a clean checkout." }

New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
Write-Host "[V0-P3 mining] Project: $ProjectRoot"
Write-Host "[V0-P3 mining] HEAD:    $Head"
Write-Host "[V0-P3 mining] Godot:   $GodotExe"

$HadBreakpointRuntimeDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$LiveExit = -1
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host ""
    Write-Host "=== V0-P3 focused domain / aggregate / wire / wiring ===" -ForegroundColor Cyan
    & (Join-Path $ProjectRoot "RUN_V0_P3_RESOURCE_MINING_DOMAIN_TESTS.ps1") `
        -GodotExe $GodotExe `
        -ExpectedHead $Head
    if ($LASTEXITCODE -ne 0) { throw "V0-P3 focused resource-mining gate failed." }
    if (git -C $ProjectRoot status --porcelain) { throw "V0-P3 focused gate changed tracked checkout state." }

    Write-Host ""
    Write-Host "=== Inherited P1/P2 exact-head reconnect regression ===" -ForegroundColor Cyan
    & (Join-Path $ProjectRoot "RUN_V0_P2_RECONNECT_GATE.ps1") `
        -GodotExe $GodotExe `
        -ExpectedHead $Head
    if ($LASTEXITCODE -ne 0) { throw "Inherited P1/P2 reconnect gate failed on V0-P3 exact head." }
    if (git -C $ProjectRoot status --porcelain) { throw "Inherited P1/P2 gate changed tracked checkout state." }

    Write-Host ""
    Write-Host "=== V0-P3 live mining + reconnect convergence ===" -ForegroundColor Cyan
    & $GodotExe `
        --headless `
        --path $ProjectRoot `
        --log-file $LiveLog `
        --script res://tests/runtime/test_v0_p3_live_resource_mining_convergence.gd
    $LiveExit = $LASTEXITCODE
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}

if ($LiveExit -ne 0) {
    Get-Content $LiveLog -Tail 360 -ErrorAction SilentlyContinue
    throw "V0-P3 live resource-mining convergence failed (exit $LiveExit)."
}

$FatalPatterns = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "Failed to load script",
    "could not listen on 127.0.0.1:9081"
)
foreach ($Pattern in $FatalPatterns) {
    if (Select-String -Path $LiveLog -SimpleMatch $Pattern -Quiet) {
        Get-Content $LiveLog -Tail 360 -ErrorAction SilentlyContinue
        throw "V0-P3 live mining log contains fatal/isolation marker: $Pattern"
    }
}

$Summary = Select-String -Path $LiveLog -Pattern 'V0-P3 live resource mining convergence: ([0-9]+) assertions, 0 failures' | Select-Object -Last 1
if ($null -eq $Summary) {
    Get-Content $LiveLog -Tail 360 -ErrorAction SilentlyContinue
    throw "V0-P3 live mining gate exited zero but did not emit trusted zero-failure summary."
}
if (git -C $ProjectRoot status --porcelain) {
    git -C $ProjectRoot status --short
    throw "V0-P3 resource-mining gate changed tracked checkout state."
}

Write-Host ""
Write-Host $Summary.Line -ForegroundColor Green
Write-Host "[V0-P3 mining] EXACT HEAD GREEN: $Head" -ForegroundColor Green
