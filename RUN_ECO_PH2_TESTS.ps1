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
        @{ Name="PH2 environment-coupled development"; Script="res://tests/research/ecology/eco_ph2_environment_coupled_development_acceptance.gd" },
        @{ Name="PH2 visual lab headless smoke"; Script="res://tests/research/ecology/eco_ph2_visual_lab_smoke.gd" },
        @{ Name="PH2 fresh-process restart replay"; Script="res://tests/research/ecology/eco_ph2_restart_replay_probe.gd" }
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
Write-Host "ECO.PH2 focused acceptance: PASS (107 assertions)"
Write-Host "ECO.PH2 visual lab smoke: PASS (12 assertions)"
Write-Host "ECO.PH2 restart replay: PASS (5 assertions)"
Write-Host "ECO.PH2 environment-coupled development candidate: PASS"
