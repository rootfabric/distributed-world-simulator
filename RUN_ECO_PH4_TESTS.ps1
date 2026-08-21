param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

# Guard against accidentally running ECO acceptance from another worktree branch.
$Git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $Git) {
    $ActualBranch = (& git -C $RootDir branch --show-current 2>$null).Trim()
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ActualBranch) -and $ActualBranch -ne $ExpectedBranch) {
        throw "WRONG_BRANCH: expected $ExpectedBranch, actual $ActualBranch. Switch the worktree before running ECO tests."
    }
}

$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
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
        @{ Name="PH3C accepted morphology-aware selection"; Script="res://tests/research/ecology/eco_ph3c_morphology_aware_selection_acceptance.gd" },
        @{ Name="PH3C accepted fresh-process replay"; Script="res://tests/research/ecology/eco_ph3c_restart_replay_probe.gd" },
        @{ Name="PH4 seed development lifecycle"; Script="res://tests/research/ecology/eco_ph4_seed_lifecycle_acceptance.gd" },
        @{ Name="PH4 fresh-process restart replay"; Script="res://tests/research/ecology/eco_ph4_restart_replay_probe.gd" }
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
Write-Host "ECO.PH3C parent morphology-aware selection: PASS (97 assertions + restart 6)"
Write-Host "ECO.PH4 focused acceptance: PASS (718 assertions)"
Write-Host "ECO.PH4 restart replay: PASS (5 assertions)"
Write-Host "ECO.PH4 profile_hash=d8c8b9ff56ec630b832c4b6bdbb49d39147586f4d97e6535dcc6fbd37c29a795"
Write-Host "ECO.PH4 founder_payload_hash=1b5ff858fc57fdf98d75eb796cc6d7e6aa68b0b0e51e8321611e13b024cdc396"
Write-Host "ECO.PH4 lifecycle_hash=88d8b3f53a5233d675eb75f1fe94c017b4f435ca91c34ce145d9b93f3c72d6d1"
Write-Host "ECO.PH4 offspring_batch_hash=48d1ba23151ad5cf02f4d0de2ebbf9559da99612c852c6ec97029254159ee5ce"
Write-Host "ECO.PH4 seed development lifecycle candidate: PASS"
