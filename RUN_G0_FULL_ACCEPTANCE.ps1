$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FocusedRunner = Join-Path $RootDir "RUN_G0_GEO_CONTRACTS_TESTS.ps1"
$WorldRunner = Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1"

foreach ($RequiredPath in @($FocusedRunner, $WorldRunner)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required G0 acceptance runner is missing: $RequiredPath"
    }
}

$PowerShellExecutable = if ($PSVersionTable.PSEdition -eq "Core") {
    Join-Path $PSHOME "pwsh.exe"
}
else {
    Join-Path $PSHOME "powershell.exe"
}
if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
    $PowerShellExecutable = (Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
}
if ([string]::IsNullOrWhiteSpace($PowerShellExecutable)) {
    throw "PowerShell executable for isolated world regression was not found."
}

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED

try {
    # Automated acceptance does not use the live Breakpoint MCP runtime socket.
    # Child Godot processes inherit this flag, eliminating expected :9081 bind
    # collisions without changing normal editor/game MCP behavior.
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G0 focused contracts ==="
    & $FocusedRunner
    if (-not $?) {
        throw "G0 focused contracts runner failed."
    }

    Write-Host "=== Full world/core regression (Breakpoint runtime disabled) ==="
    & $PowerShellExecutable `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $WorldRunner

    if ($LASTEXITCODE -ne 0) {
        throw "World/core regression failed with exit code $LASTEXITCODE"
    }

    Write-Host "=== Git diff hygiene ==="
    $BaseRef = "origin/feature/g0-procedural-planetary-generation-lab"
    & git -C $RootDir rev-parse --verify $BaseRef *> $null
    if ($LASTEXITCODE -ne 0) {
        $BaseRef = "feature/g0-procedural-planetary-generation-lab"
    }

    & git -C $RootDir diff --check "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed against $BaseRef"
    }

    Write-Host "G0 full acceptance gate: PASS"
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}
