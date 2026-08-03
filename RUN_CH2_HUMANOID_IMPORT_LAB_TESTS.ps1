param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.1 double executable is required via -GodotPath or GODOT_BIN."
}
& $GodotPath --headless --editor --path $Root --quit
if ($LASTEXITCODE -ne 0) { throw "CH2 editor import failed: $LASTEXITCODE" }
& $GodotPath --headless --path $Root --script res://tests/characters/test_ch1_character_contracts_and_registry.gd
if ($LASTEXITCODE -ne 0) { throw "CH1 regression failed: $LASTEXITCODE" }
& $GodotPath --headless --path $Root --script res://tests/characters/test_ch2_humanoid_import_lab.gd
if ($LASTEXITCODE -ne 0) { throw "CH2 focused tests failed: $LASTEXITCODE" }
