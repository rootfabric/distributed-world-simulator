param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
& $GodotPath --path $RootDir "res://scenes/labs/ecology/eco_obs1_spatial_observer_lab.tscn"
if ($LASTEXITCODE -ne 0) { throw "ECO OBS1.2 spatial lab exited with code $LASTEXITCODE" }
