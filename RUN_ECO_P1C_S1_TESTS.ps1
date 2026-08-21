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
        Write-Host "ECO.P1C-S1 preflight: initializing Godot import/UID cache"
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
        @{ Name = "P1B-S4 parent regression"; Script = "res://tests/research/ecology/eco_p1b_s4_local_adaptation_robustness_acceptance.gd" },
        @{ Name = "P1C-S1 strategy competition baseline"; Script = "res://tests/research/ecology/eco_p1c_s1_strategy_competition_acceptance.gd" },
        @{ Name = "P1C-S1 fresh-process replay"; Script = "res://tests/research/ecology/eco_p1c_s1_restart_replay_probe.gd" }
    )

    foreach ($Test in $Tests) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) { throw "$($Test.Name) failed with exit code $LASTEXITCODE" }
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
Write-Host "ECO.P1B-S4 parent regression: PASS (86 assertions)"
Write-Host "ECO.P1C-S1 focused acceptance: PASS (116 assertions)"
Write-Host "ECO.P1C-S1 restart replay: PASS (5 assertions)"
Write-Host "ECO.P1C-S1 result_hash=cf3bd5f417c9a49dd1c5eac0d93ea736b02ec0be25afd4945b1424a8dbde3928"
Write-Host "ECO.P1C-S1 uniform_hash=1c5128666314dfeec9ed09094931be58e76253f92bf9da50379a91eeb3b68a58"
Write-Host "ECO.P1C-S1 alt_result_hash=bded62e12ade0285c019d0dc2e4f77d0d6cb88431df7ade605160e0f18d82f8c"
Write-Host "ECO.P1C-S1 founder_pool_hash=77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38"
Write-Host "ECO.P1C-S1 strategy competition candidate: PASS"
