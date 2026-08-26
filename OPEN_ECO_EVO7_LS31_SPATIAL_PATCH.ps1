param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
& $GodotPath --path $RootDir --resolution 1600x900 res://scenes/labs/ecology/eco_evo7_ls31_spatial_patch_lab.tscn
if ($LASTEXITCODE -ne 0) { throw "ECO.EVO7 LS3.0/LS3.1 spatial patch lab failed with exit code $LASTEXITCODE" }
