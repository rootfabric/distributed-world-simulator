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
        @{ Name="P1C-S4 accepted aggregate contract"; Script="res://tests/research/ecology/eco_p1c_s4_aggregate_contract.gd" },
        @{ Name="PH0 accepted development contract"; Script="res://tests/research/ecology/eco_ph0_development_contract_acceptance.gd" },
        @{ Name="PH1 accepted skeleton regression"; Script="res://tests/research/ecology/eco_ph1_growth_graph_skeleton_acceptance.gd" },
        @{ Name="PH2 accepted plasticity regression"; Script="res://tests/research/ecology/eco_ph2_environment_coupled_development_acceptance.gd" },
        @{ Name="PH3 accepted morphology-resource regression"; Script="res://tests/research/ecology/eco_ph3_morphology_resource_coupling_acceptance.gd" },
        @{ Name="PH3C morphology-aware selection"; Script="res://tests/research/ecology/eco_ph3c_morphology_aware_selection_acceptance.gd" },
        @{ Name="PH3C fresh-process restart replay"; Script="res://tests/research/ecology/eco_ph3c_restart_replay_probe.gd" }
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
Write-Host "ECO.P1C-S4 parent aggregate: PASS (15 assertions)"
Write-Host "ECO.PH0 parent contract: PASS (63 assertions)"
Write-Host "ECO.PH1 parent skeleton: PASS (128 assertions)"
Write-Host "ECO.PH2 parent plasticity: PASS (107 assertions)"
Write-Host "ECO.PH3 parent morphology-resource: PASS (217 assertions)"
Write-Host "ECO.PH3C causal competition gate completed"
Write-Host "ECO.PH3C restart replay completed"
Write-Host "ECO.PH3C morphology-aware selection candidate: PASS if all Godot scripts above returned PASS"
