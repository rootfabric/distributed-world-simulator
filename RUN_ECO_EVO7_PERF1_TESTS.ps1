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
    throw "ECO.EVO7 PERF1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
$Tests = @(
    'res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd',
    'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd',
    'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd'
)
foreach ($Test in $Tests) {
    & $GodotBin --headless --path $Root --script $Test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
