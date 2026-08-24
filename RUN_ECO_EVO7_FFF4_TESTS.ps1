param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE" }
    }
    $Tests = @(
        @{ Name="FFF4 water feedback acceptance"; Script="res://tests/research/ecology/eco_evo7_fff4_water_feedback_acceptance.gd" },
        @{ Name="FFF3 light feedback chain"; Script="res://tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd" },
        @{ Name="FFF2 morphology evolution chain"; Script="res://tests/research/ecology/eco_evo7_fff2_morphology_evolution_acceptance.gd" },
        @{ Name="FFF1 functional phenotype chain"; Script="res://tests/research/ecology/eco_evo7_fff1_functional_phenotype_acceptance.gd" },
        @{ Name="FFF0 contract mapping chain"; Script="res://tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd" },
        @{ Name="P1B-S1 mutation lineage kernel dependency"; Script="res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd" },
        @{ Name="PH2 environment-coupled development dependency"; Script="res://tests/research/ecology/eco_ph2_environment_coupled_development_acceptance.gd" },
        @{ Name="P1A-S1 parent environment regression"; Script="res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd" },
        @{ Name="P1A-S2 parent resource regression"; Script="res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd" },
        @{ Name="P1C-S4 parent aggregate regression"; Script="res://tests/research/ecology/eco_p1c_s4_aggregate_contract.gd" },
        @{ Name="PH0 development trait contract regression"; Script="res://tests/research/ecology/eco_ph0_development_contract_acceptance.gd" }
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
Write-Host "ECO.EVO7 FFF4 Water Feedback candidate: PASS"
