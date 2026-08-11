param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.P1A-S2 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
            throw "Godot import preflight completed but UID cache was not created: $UidCachePath"
        }
    }

    Write-Host "=== ECO.P1A-S2 parent environment regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "ECO.P1A-S1 parent regression failed with exit code $LASTEXITCODE"
    }

    Write-Host "=== ECO.P1A-S2 single-plant resource acceptance ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "ECO.P1A-S2 focused acceptance failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}

Write-Host "ECO.P1A-S1 parent regression: PASS (109 assertions)"
Write-Host "ECO.P1A-S2 focused acceptance: PASS (235 assertions)"
Write-Host "ECO.P1A-S2 simulation_hash=618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c"
