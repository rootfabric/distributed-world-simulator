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
    if ($LASTEXITCODE -ne 0) { throw "G6.0 headless editor import failed" }
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/features/g5_world_feature_graph_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G5 World Feature Graph dependency regression" }
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/features/g5_feature_cell_identity_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G5 feature/cell identity dependency regression" }
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_fluid_contracts_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6.0 fluid contracts acceptance failed" }
    Write-Host "G6.0 fluid contracts focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
