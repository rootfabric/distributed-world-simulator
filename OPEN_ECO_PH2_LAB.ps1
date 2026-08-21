param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$GuiPath = $GodotPath -replace '\.console\.exe$', '.exe'
if (-not (Test-Path -LiteralPath $GuiPath -PathType Leaf)) { $GuiPath = $GodotPath }
Write-Host "Opening ECO.PH2 Plasticity Visual Lab with $GuiPath"
Start-Process -FilePath $GuiPath -WorkingDirectory $RootDir -ArgumentList @('--path', $RootDir, 'res://scenes/labs/ecology/eco_ph2_plasticity_visual_lab.tscn')
