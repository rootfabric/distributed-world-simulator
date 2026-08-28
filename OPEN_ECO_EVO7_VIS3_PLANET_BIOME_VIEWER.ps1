param(
    [string]$GodotBin = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Scene = 'res://scenes/labs/ecology/eco_evo7_vis3_planet_biome_viewer.tscn'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS3 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
Write-Host "ECO.EVO7 VIS3 launching explicit scene: $Scene"
& $GodotBin --path $Root --resolution 1600x900 --scene $Scene
exit $LASTEXITCODE
