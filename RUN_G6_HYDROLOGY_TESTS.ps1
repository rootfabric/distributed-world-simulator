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
$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExecutable --headless --editor --path $RootDir --quit
    if ($LASTEXITCODE -ne 0) { throw "G6 headless editor import failed" }
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_hydrology_fluid_surface_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6 hydrology/fluid surface acceptance failed" }
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_river_cell_lod_identity_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6 river/cell LOD identity acceptance failed" }
    & $GodotExecutable --headless --path $RootDir --scene "res://scenes/labs/procedural/g6_hydrology_fluid_surface_lab.tscn" --quit-after 2
    if ($LASTEXITCODE -ne 0) { throw "G6 visual lab headless launch failed" }
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
