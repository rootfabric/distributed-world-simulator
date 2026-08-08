$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$GodotExecutable = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $GodotExecutable) { throw "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision console/editor binary." }
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
& $GodotExecutable --headless --editor --path $RootDir --quit
if ($LASTEXITCODE -ne 0) { throw "G3 headless editor import failed" }
& $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/surface/g3_macro_surface_acceptance.gd"
if ($LASTEXITCODE -ne 0) { throw "G3 macro surface acceptance failed" }
& $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/surface/g3_fly_in_macro_continuity.gd"
if ($LASTEXITCODE -ne 0) { throw "G3 fly-in macro continuity failed" }
& $GodotExecutable --headless --path $RootDir --scene "res://scenes/labs/procedural/g3_casual_macro_surface_lab.tscn" --quit-after 2
if ($LASTEXITCODE -ne 0) { throw "G3 visual lab headless launch failed" }
