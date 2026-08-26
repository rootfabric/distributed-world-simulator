param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
& $GodotPath --path $RootDir --resolution 1600x900 res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn
if ($LASTEXITCODE -ne 0) { throw "ECO.EVO7 FFF6 lab failed with exit code $LASTEXITCODE" }
