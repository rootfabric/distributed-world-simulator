$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FocusedRunner = Join-Path $RootDir "RUN_G1_GEODESY_TESTS.ps1"
$WorldRunner = Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1"
$RegressionArtifacts = Join-Path $RootDir "artifacts\test-results"

foreach ($RequiredPath in @($FocusedRunner, $WorldRunner)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required G1 acceptance runner is missing: $RequiredPath"
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
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G1 focused geodesy ==="
    & $FocusedRunner
    if (-not $?) {
        throw "G1 focused geodesy runner failed."
    }

    Write-Host "=== Full world/core regression (Breakpoint runtime disabled) ==="
    $RegressionStartedUtc = [DateTime]::UtcNow
    & $PowerShellExecutable `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $WorldRunner

    if ($LASTEXITCODE -ne 0) {
        throw "World/core regression failed with exit code $LASTEXITCODE"
    }

    Write-Host "=== Regression log-noise audit ==="
    $BreakpointCollisionPattern = "[breakpoint_runtime] could not listen on 127.0.0.1:9081"
    $BreakpointCollisionHits = @()
    if (Test-Path -LiteralPath $RegressionArtifacts -PathType Container) {
        $AuditFloorUtc = $RegressionStartedUtc.AddSeconds(-2)
        $BreakpointCollisionHits = @(
            Get-ChildItem -LiteralPath $RegressionArtifacts -Recurse -File -Filter "*.log" |
                Where-Object { $_.LastWriteTimeUtc -ge $AuditFloorUtc } |
                Select-String -SimpleMatch $BreakpointCollisionPattern
        )
    }
    if ($BreakpointCollisionHits.Count -gt 0) {
        $Locations = $BreakpointCollisionHits |
            ForEach-Object { "{0}:{1}" -f $_.Path, $_.LineNumber }
        throw (
            "Breakpoint runtime port-collision noise remained in current regression logs ({0} hits):`n{1}" -f `
                $BreakpointCollisionHits.Count,
                ($Locations -join [Environment]::NewLine)
        )
    }
    Write-Host "Breakpoint runtime :9081 collision noise: 0"

    Write-Host "=== Git diff hygiene ==="
    $BaseRef = "origin/feature/g0-geo-contracts"
    & git -C $RootDir rev-parse --verify $BaseRef *> $null
    if ($LASTEXITCODE -ne 0) {
        $BaseRef = "feature/g0-geo-contracts"
    }

    & git -C $RootDir diff --check "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed against $BaseRef"
    }

    Write-Host "G1 full acceptance gate: PASS"
}
finally {
    if ($HadBreakpointRuntimeDisabled) {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled
    }
    else {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
}
