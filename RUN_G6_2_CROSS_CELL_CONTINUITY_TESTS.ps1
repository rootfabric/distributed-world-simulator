$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G61Runner = Join-Path $RootDir "RUN_G6_1_CASUAL_RIVER_PROVIDER_TESTS.ps1"
if (-not (Test-Path -LiteralPath $G61Runner -PathType Leaf)) { throw "G6.1 dependency runner is missing: $G61Runner" }

Write-Host "=== G6.1 accepted dependency gate ==="
& $G61Runner
if (-not $?) { throw "G6.1 dependency gate failed." }

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
    Write-Host "=== G6.2 cross-cell / cross-LOD continuity ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_2_cross_cell_cross_lod_continuity_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6.2 cross-cell/cross-LOD continuity acceptance failed" }
    Write-Host "G6.2 cross-cell/cross-LOD continuity focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
