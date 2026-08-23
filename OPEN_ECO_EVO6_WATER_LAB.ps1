param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

& $GodotPath --path $RootDir --resolution 1600x900 res://scenes/labs/ecology/eco_evo6_water_evolution_lab.tscn
if ($LASTEXITCODE -ne 0) {
    throw "ECO.EVO6-WATER visual lab failed with exit code $LASTEXITCODE"
}
