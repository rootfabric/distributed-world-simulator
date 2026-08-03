param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.1 double executable is required via -GodotPath or GODOT_BIN."
}
& $GodotPath --headless --editor --path $Root --quit
if ($LASTEXITCODE -ne 0) { throw "CH3 editor import failed: $LASTEXITCODE" }
$Tests = @(
    "res://tests/characters/test_ch1_character_contracts_and_registry.gd",
    "res://tests/characters/test_ch2_humanoid_import_lab.gd",
    "res://tests/characters/test_ch3_isolated_presentation_host.gd"
)
foreach ($Test in $Tests) {
    & $GodotPath --headless --path $Root --script $Test
    if ($LASTEXITCODE -ne 0) { throw "Character test failed: $Test ($LASTEXITCODE)" }
}
& $GodotPath --audio-driver Dummy --path $Root --rendering-method gl_compatibility --script res://tests/characters/test_ch3_character_lab_graphical.gd
if ($LASTEXITCODE -ne 0) { throw "CH3 graphical smoke failed: $LASTEXITCODE" }
