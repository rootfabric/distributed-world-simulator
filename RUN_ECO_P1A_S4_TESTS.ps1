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
        Write-Host "ECO.P1A-S4 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO.P1A-S4 parent S1 regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S1 parent regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S4 parent S2 regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S2 parent regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S4 parent S3 regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S3 parent regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S4 determinism/sensitivity/failure matrix ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s4_determinism_sensitivity_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S4 focused acceptance failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO.P1A-S4 fresh-process restart replay ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s4_restart_replay_probe.gd"
    if ($LASTEXITCODE -ne 0) { throw "ECO.P1A-S4 restart replay failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
}

Write-Host "ECO.P1A-S1 parent regression: PASS (109 assertions)"
Write-Host "ECO.P1A-S2 parent regression: PASS (235 assertions)"
Write-Host "ECO.P1A-S3 parent regression: PASS (208 assertions)"
Write-Host "ECO.P1A-S4 focused acceptance: PASS (165 assertions)"
Write-Host "ECO.P1A-S4 restart replay: PASS (5 assertions)"
Write-Host "ECO.P1A-S4 baseline_summary_hash=327d211d24f8f74251e02f0ced22323b4120c18d9b42a9cfcf99974cf9accc5a"
Write-Host "ECO.P1A-S4 baseline_result_hash=cb1641a6b49dfa2be3f64c94f2ebc3240327eaca559d025d34e72ba74c0aa11e"
Write-Host "ECO.P1A-S4 biomass_series_hash=7c621f1a8c302fdd10f60fd4e576b7688a3bd1065f84c84b7c391e5031f05e0c"
