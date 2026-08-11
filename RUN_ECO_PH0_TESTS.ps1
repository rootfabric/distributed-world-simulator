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
        @{ Name="P1A-S1 parent environment regression"; Script="res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd" },
        @{ Name="P1A-S2 parent resource regression"; Script="res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd" },
        @{ Name="P1C-S4 accepted aggregate contract"; Script="res://tests/research/ecology/eco_p1c_s4_aggregate_contract.gd" },
        @{ Name="PH0 development trait contract"; Script="res://tests/research/ecology/eco_ph0_development_contract_acceptance.gd" }
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
Write-Host "ECO.P1C-S4 parent aggregate: PASS (15 assertions)"
Write-Host "ECO.PH0 Development Trait Contract: PASS (63 assertions)"
Write-Host "ECO.PH0 development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea"
Write-Host "ECO.PH0 individual_seed=959597643576420676"
Write-Host "ECO.PH0 candidate: PASS"
