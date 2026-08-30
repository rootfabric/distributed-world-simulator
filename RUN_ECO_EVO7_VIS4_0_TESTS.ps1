param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS4.0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    & (Join-Path $RootDir "RUN_ECO_EVO7_FFF2_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "FFF2 parent regression failed" }

    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "VIS4.0 truth contract audit failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}
Write-Host "ECO.EVO7 VIS4.0 Truth / Contract Audit candidate: PASS"
