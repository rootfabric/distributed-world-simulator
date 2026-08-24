$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @($env:GODOT_BIN)
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Godot) {
    throw "Double-precision Godot editor was not found. Set GODOT_BIN."
}

& $Godot --headless --path $ProjectRoot --script res://tests/runtime/test_mvp_procedural_planet_spawn.gd
exit $LASTEXITCODE
