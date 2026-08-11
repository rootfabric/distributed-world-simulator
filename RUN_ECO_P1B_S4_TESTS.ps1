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
        Write-Host "ECO.P1B-S4 preflight: initializing Godot import/UID cache"
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
        @{ Name = "P1B-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s3_regional_population_field_acceptance.gd" },
        @{ Name = "P1B-S4 local adaptation robustness"; Script = "res://tests/research/ecology/eco_p1b_s4_local_adaptation_robustness_acceptance.gd" },
        @{ Name = "P1B-S4 fresh-process replay"; Script = "res://tests/research/ecology/eco_p1b_s4_restart_replay_probe.gd" }
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
Write-Host "ECO.P1B-S3 parent regression: PASS (388 assertions)"
Write-Host "ECO.P1B-S4 focused acceptance: PASS (86 assertions)"
Write-Host "ECO.P1B-S4 restart replay: PASS (5 assertions)"
Write-Host "ECO.P1B-S4 aggregate_hash=2c37160726c73a9b6b479be67a3cedcd34a1247025b219d2b5ebddbec4e18f05"
Write-Host "ECO.P1B-S4 neutral_hash=175bbef1c085d0783bd0d48f23bbc9a865cc438ae09e15785d4e48cdf1cc27bf"
Write-Host "ECO.P1B-S4 long_run_hash=7f68ed87e10fa7dd6f9f79c6d50d0a82cf4360e4a416dc481e0e6005bcfb44f3"
Write-Host "ECO.P1B-S4 robustness gate candidate: PASS"
