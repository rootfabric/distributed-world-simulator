param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.P1C-S4 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }

    $Parents = @(
        @{ Name = "P1A-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"; Args = @() },
        @{ Name = "P1A-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd"; Args = @() },
        @{ Name = "P1A-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s3_visual_lab_acceptance.gd"; Args = @() },
        @{ Name = "P1A-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1a_s4_determinism_sensitivity_acceptance.gd"; Args = @() },
        @{ Name = "P1B-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd"; Args = @() },
        @{ Name = "P1B-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s2_spatial_selection_acceptance.gd"; Args = @() },
        @{ Name = "P1B-S3 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s3_regional_population_field_acceptance.gd"; Args = @() },
        @{ Name = "P1B-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s4_local_adaptation_robustness_acceptance.gd"; Args = @() },
        @{ Name = "P1C-S1 parent regression"; Script = "res://tests/research/ecology/eco_p1c_s1_strategy_competition_acceptance.gd"; Args = @() },
        @{ Name = "P1C-S2 parent regression"; Script = "res://tests/research/ecology/eco_p1c_s2_dynamic_abundance_acceptance.gd"; Args = @() },
        @{ Name = "P1C-S3 parent representative regression"; Script = "res://tests/research/ecology/eco_p1c_s3_niche_cluster_seed_acceptance.gd"; Args = @("1138701","false") }
    )
    foreach ($Test in $Parents) {
        Write-Host "=== ECO $($Test.Name) ==="
        if ($Test.Args.Count -eq 0) { & $GodotPath --headless --path $RootDir --script $Test.Script }
        else { & $GodotPath --headless --path $RootDir --script $Test.Script -- $Test.Args }
        if ($LASTEXITCODE -ne 0) { throw "$($Test.Name) failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO P1C-S3 parent aggregate contract ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s3_aggregate_contract.gd"
    if ($LASTEXITCODE -ne 0) { throw "P1C-S3 parent aggregate contract failed with exit code $LASTEXITCODE" }

    $Cases = @(
        @{ Name="S4 seed 1138701"; Seed="1138701"; Cycles="18"; Uniform="false" },
        @{ Name="S4 seed 1138702"; Seed="1138702"; Cycles="18"; Uniform="false" },
        @{ Name="S4 seed 1138703"; Seed="1138703"; Cycles="18"; Uniform="false" },
        @{ Name="S4 seed 1138704"; Seed="1138704"; Cycles="18"; Uniform="false" },
        @{ Name="S4 seed 1138705"; Seed="1138705"; Cycles="18"; Uniform="false" },
        @{ Name="S4 seed 1138706"; Seed="1138706"; Cycles="18"; Uniform="false" },
        @{ Name="S4 uniform negative control"; Seed="1138701"; Cycles="18"; Uniform="true" },
        @{ Name="S4 deep horizon"; Seed="1138701"; Cycles="24"; Uniform="false" }
    )
    foreach ($Case in $Cases) {
        Write-Host "=== ECO P1C-$($Case.Name) ==="
        & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s4_robustness_seed_acceptance.gd" -- $Case.Seed $Case.Cycles $Case.Uniform
        if ($LASTEXITCODE -ne 0) { throw "$($Case.Name) failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO P1C-S4 aggregate contract ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s4_aggregate_contract.gd"
    if ($LASTEXITCODE -ne 0) { throw "P1C-S4 aggregate contract failed with exit code $LASTEXITCODE" }

    Write-Host "=== ECO P1C-S4 fresh-process restart replay ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1c_s4_restart_replay_probe.gd"
    if ($LASTEXITCODE -ne 0) { throw "P1C-S4 restart replay failed with exit code $LASTEXITCODE" }
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
Write-Host "ECO.P1C-S3 parent representative: PASS (64 assertions + aggregate 5)"
Write-Host "ECO.P1C-S4 robustness matrix: PASS (6x30 heterogeneous, 27 uniform, 30 deep-horizon assertions)"
Write-Host "ECO.P1C-S4 aggregate contract: PASS (15 assertions)"
Write-Host "ECO.P1C-S4 restart replay: PASS (6 assertions)"
Write-Host "ECO.P1C-S4 aggregate_hash=0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112"
Write-Host "ECO.P1C-S4 default_case_hash=431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b"
Write-Host "ECO.P1C-S4 uniform_case_hash=8f27fb89d87d7b92911efcb80ae461d2d0f32ff169ed8f3efbdf73a296d67d47"
Write-Host "ECO.P1C-S4 deep_horizon_case_hash=ca49a238f82303ac6ad7e36d10f849baff07442873ab3b20c22d2d32f9f34411"
Write-Host "ECO.P1C-S4 competition robustness candidate: PASS"
