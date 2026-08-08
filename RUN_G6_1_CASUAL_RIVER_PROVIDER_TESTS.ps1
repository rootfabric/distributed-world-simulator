$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G60Runner = Join-Path $RootDir "RUN_G6_FLUID_CONTRACT_TESTS.ps1"
if (-not (Test-Path -LiteralPath $G60Runner -PathType Leaf)) { throw "G6.0 dependency runner is missing: $G60Runner" }

Write-Host "=== G6.0 accepted dependency gate ==="
& $G60Runner
if (-not $?) { throw "G6.0 dependency gate failed." }

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
    Write-Host "=== G6.1 CasualRiverProviderV1 ==="
    & $GodotExecutable --headless --path $RootDir --script "res://tests/procedural/hydrology/g6_1_casual_river_provider_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "G6.1 CasualRiverProviderV1 acceptance failed" }
    Write-Host "G6.1 CasualRiverProviderV1 focused gate passed."
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
