$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G62Runner = Join-Path $RootDir "RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1"
if (-not (Test-Path -LiteralPath $G62Runner -PathType Leaf)) { throw "G6.2 dependency runner is missing: $G62Runner" }

Write-Host "=== G6.2 accepted dependency gate ==="
& $G62Runner
if (-not $?) { throw "G6.2 dependency gate failed." }

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
    Write-Host "=== G6.3 runtime WaterSurfaceQuery ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_3_runtime_water_surface_query_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6.3 runtime WaterSurfaceQuery acceptance failed" }
    Write-Host "G6.3 runtime WaterSurfaceQuery focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
