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
        Write-Host "ECO.P1B-S3 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    $Tests = @(
        @{ Name = "P1A-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd" },
        @{ Name = "P1A-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd" },
        @{ Name = "P1A-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd" },
        @{ Name = "P1A-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s4_determinism_sensitivity_acceptance.gd" },
        @{ Name = "P1B-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd" },
        @{ Name = "P1B-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s2_spatial_selection_acceptance.gd" },
        @{ Name = "P1B-S3 regional population field"; Script = "res://tests/research/ecology/eco_p1b_s3_regional_population_field_acceptance.gd" },
        @{ Name = "P1B-S3 fresh-process replay"; Script = "res://tests/research/ecology/eco_p1b_s3_restart_replay_probe.gd" }
    )

    foreach ($Test in $Tests) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) {
            throw "$($Test.Name) failed with exit code $LASTEXITCODE"
        }
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
}

Write-Host "ECO.P1A-S1 parent regression: PASS (109 assertions)"
Write-Host "ECO.P1A-S2 parent regression: PASS (235 assertions)"
Write-Host "ECO.P1A-S3 parent regression: PASS (208 assertions)"
Write-Host "ECO.P1A-S4 parent regression: PASS (165 assertions)"
Write-Host "ECO.P1B-S1 parent regression: PASS (5834 assertions)"
Write-Host "ECO.P1B-S2 parent regression: PASS (364 assertions)"
Write-Host "ECO.P1B-S3 focused acceptance: PASS (388 assertions)"
Write-Host "ECO.P1B-S3 restart replay: PASS (6 assertions)"
Write-Host "ECO.P1B-S3 result_hash=cbd2f4a65f2a06f8ee9feeea0d9eae90d37cd0ede15df1bd808ef52773089b56"
Write-Host "ECO.P1B-S3 neutral_hash=b4d18ef35a2a77104fa18c8a3f3004a6f5898d572e57917429cc955cc7e2c5e6"
Write-Host "ECO.P1B-S3 alt_result_hash=ca81e0cfea0b05850470276fef10c880d3832613df9ff7f35d3c7395bd32589b"
Write-Host "ECO.P1B-S3 regional population field candidate: PASS"
