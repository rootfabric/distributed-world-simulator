param(
    [string]$GodotBin = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS3 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
& "$Root\RUN_ECO_EVO7_VIS2_TESTS.ps1" -GodotBin $GodotBin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotBin --headless --path $Root --script 'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd'
exit $LASTEXITCODE
