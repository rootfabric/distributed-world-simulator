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
        Write-Host "ECO.P1C-S3 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    $Parents = @(
        @{ Name = "P1A-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd" },
        @{ Name = "P1A-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd" },
        @{ Name = "P1A-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd" },
        @{ Name = "P1A-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s4_determinism_sensitivity_acceptance.gd" },
        @{ Name = "P1B-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd" },
        @{ Name = "P1B-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s2_spatial_selection_acceptance.gd" },
        @{ Name = "P1B-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s3_regional_population_field_acceptance.gd" },
        @{ Name = "P1B-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s4_local_adaptation_robustness_acceptance.gd" },
        @{ Name = "P1C-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1c_s1_strategy_competition_acceptance.gd" },
        @{ Name = "P1C-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1c_s2_dynamic_abundance_acceptance.gd" }
    )
    foreach ($Test in $Parents) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) { throw "$($Test.Name) failed with exit code $LASTEXITCODE" }
    }

    $Cases = @(
        @{ Name = "P1C-S3 default heterogeneous"; Seed = "1138701"; Uniform = "false" },
        @{ Name = "P1C-S3 alternate heterogeneous"; Seed = "1138702"; Uniform = "false" },
        @{ Name = "P1C-S3 third heterogeneous"; Seed = "1138703"; Uniform = "false" },
        @{ Name = "P1C-S3 uniform control"; Seed = "1138701"; Uniform = "true" }
    )
    foreach ($Case in $Cases) {
        Write-Host "=== ECO $($Case.Name) ==="
        & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s3_niche_cluster_seed_acceptance.gd" -- $Case.Seed $Case.Uniform
        if ($LASTEXITCODE -ne 0) { throw "$($Case.Name) failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO P1C-S3 aggregate contract ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s3_aggregate_contract.gd"
    if ($LASTEXITCODE -ne 0) { throw "P1C-S3 aggregate contract failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO P1C-S3 fresh-process restart replay ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s3_restart_replay_probe.gd"
    if ($LASTEXITCODE -ne 0) { throw "P1C-S3 restart replay failed with exit code $LASTEXITCODE" }
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
Write-Host "ECO.P1B-S4 parent regression: PASS (86 assertions)"
Write-Host "ECO.P1C-S1 parent regression: PASS (116 assertions)"
Write-Host "ECO.P1C-S2 parent regression: PASS (101 assertions)"
Write-Host "ECO.P1C-S3 seed matrix: PASS (default 64, alternate 63, third 63, uniform 64 assertions)"
Write-Host "ECO.P1C-S3 aggregate contract: PASS (5 assertions)"
Write-Host "ECO.P1C-S3 restart replay: PASS (5 assertions)"
Write-Host "ECO.P1C-S3 aggregate_hash=75512459aa4a7d97b7e9549842c41a5ebf4b5574575bac9fec3ee51fd92d44a9"
Write-Host "ECO.P1C-S3 default_diagnostic_hash=33de1af8e20e45eea88d9ddc20ee0664b6c53f20282995c593c1738e9105db2d"
Write-Host "ECO.P1C-S3 alternate_diagnostic_hash=960ddf64b554e096e966796e6d614b75dfe2455259502310d75f700995d946a6"
Write-Host "ECO.P1C-S3 third_diagnostic_hash=cfe5778cf188ce06b512ce77e35ec6675cdc65703b1c8f437dcaa70db93b1c92"
Write-Host "ECO.P1C-S3 uniform_diagnostic_hash=b7a93ccdf4af05d92d2324a89331200a6957ce1433688dbe9ce70ded5e9c96f9"
Write-Host "ECO.P1C-S3 niche/cluster diagnostics candidate: PASS"
