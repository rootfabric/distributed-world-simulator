$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$GodotBin = if ($env:GODOT_BIN) {
    $env:GODOT_BIN
}
else {
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}

if (-not (Test-Path $GodotBin)) {
    throw "Godot binary not found: $GodotBin"
}

& $GodotBin --headless --path $RepoRoot --script res://tests/research/fabric_bake0/fabric_bake_b0_0_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "FABRIC-BAKE B0.0 focused acceptance failed with exit code $LASTEXITCODE"
}
