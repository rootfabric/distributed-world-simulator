param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$GuiGodot = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiGodot -PathType Leaf)) { $GuiGodot = $GodotPath }
Write-Host "Opening ECO.PH5 render materialization lab"
Write-Host "Godot: $GuiGodot"
Write-Host "Scene: res://scenes/labs/ecology/eco_ph5_render_materialization_lab.tscn"
Write-Host "Controls: Q/E = environment; A/D or Left/Right = renderer profile; Up/Down = zoom"
& $GuiGodot --path $RootDir --editor-pid 0 res://scenes/labs/ecology/eco_ph5_render_materialization_lab.tscn
