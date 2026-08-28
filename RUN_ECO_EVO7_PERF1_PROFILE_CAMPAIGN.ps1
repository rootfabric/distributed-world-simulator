param(
    [string]$GodotBin = $env:GODOT_BIN,
    [int]$Generations = 12
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PERF1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
$env:ECO_PERF1_GENERATIONS = [Math]::Max(1, [Math]::Min(100, $Generations)).ToString()
& $GodotBin --headless --path $Root --script 'res://scripts/ecology/perf/eco_evo7_perf1_profile_campaign_v1.gd'
exit $LASTEXITCODE
