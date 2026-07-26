$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
    $Candidates += $env:GODOT_BIN
}

foreach ($CommandName in @(
    "godot.windows.editor.double.x86_64.console.exe",
    "godot.windows.editor.double.x86_64.exe",
    "godot4",
    "godot"
)) {
    $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        $Candidates += $Command.Source
    }
}

$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)

$Godot = $Candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
    Select-Object -Unique |
    Select-Object -First 1

if ($null -eq $Godot) {
    throw "Double-precision Godot editor was not found. Set GODOT_BIN or add Godot to PATH."
}

$Tests = @(
    "res://tests/unit/test_simulation_clock.gd",
    "res://tests/unit/test_reference_frame_graph.gd",
    "res://tests/unit/test_celestial_motion.gd",
    "res://tests/unit/test_partition_address_v2.gd",
    "res://tests/unit/test_cube_sphere_grid.gd",
    "res://tests/unit/test_partition_foundation.gd",
    "res://tests/integration/test_entity_registry_migration.gd",
    "res://tests/integration/test_persistence_roundtrip.gd"
)

foreach ($TestScript in $Tests) {
    Write-Host "Running $TestScript"
    & $Godot --headless --path $ProjectRoot --script $TestScript
    if ($LASTEXITCODE -ne 0) {
        throw "Coordinate foundation test failed: $TestScript"
    }
}

Write-Host "Coordinate foundation tests passed."
