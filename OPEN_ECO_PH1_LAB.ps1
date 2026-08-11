param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scene = "res://scenes/labs/ecology/eco_ph1_growth_graph_visual_lab.tscn"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

# Prefer the windowed companion binary when the caller supplied the console build.
$GuiGodotPath = $GodotPath
if ($GodotPath.EndsWith(".console.exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    $Candidate = $GodotPath.Substring(0, $GodotPath.Length - ".console.exe".Length) + ".exe"
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        $GuiGodotPath = $Candidate
    }
}

Write-Host "Opening ECO.PH1 graphical lab"
Write-Host "Godot: $GuiGodotPath"
Write-Host "Scene: $Scene"
Write-Host "Controls: Q/E or Left/Right = probe; Up/Down = zoom"

Start-Process -FilePath $GuiGodotPath -WorkingDirectory $RootDir -ArgumentList @(
    "--path", $RootDir,
    $Scene
)
