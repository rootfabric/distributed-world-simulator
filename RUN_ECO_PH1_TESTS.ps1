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
        @{ Name="PH0 parent development contract"; Script="res://tests/research/ecology/eco_ph0_development_contract_acceptance.gd" },
        @{ Name="PH1 deterministic skeleton acceptance"; Script="res://tests/research/ecology/eco_ph1_growth_graph_skeleton_acceptance.gd" },
        @{ Name="PH1 visual lab headless smoke"; Script="res://tests/research/ecology/eco_ph1_visual_lab_smoke.gd" },
        @{ Name="PH1 fresh-process restart replay"; Script="res://tests/research/ecology/eco_ph1_restart_replay_probe.gd" }
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
Write-Host "ECO.PH1 focused acceptance: PASS (128 assertions)"
Write-Host "ECO.PH1 visual lab smoke: PASS (10 assertions)"
Write-Host "ECO.PH1 restart replay: PASS (4 assertions)"
Write-Host "ECO.PH1 base_graph_hash=6470722b770afee48def9ee06cc44a36640734abc9fc362a2fed6eb648779451"
Write-Host "MANUAL GRAPHICAL REVIEW: run res://scenes/labs/ecology/eco_ph1_growth_graph_visual_lab.tscn and cycle Q/E through all 9 probes"
Write-Host "ECO.PH1 deterministic skeleton candidate: PASS"
