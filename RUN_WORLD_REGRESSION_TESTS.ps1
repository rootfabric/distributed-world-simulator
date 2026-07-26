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

Write-Host "Godot: $Godot"

$Tests = @(
    "res://tests/unit/test_simulation_clock.gd",
    "res://tests/core/test_command_registry.gd",
    "res://tests/core/test_world_catalog.gd",
    "res://tests/core/test_controller_profiles.gd",
    "res://tests/unit/test_jetpack_controller.gd",
    "res://tests/unit/test_reference_frame_graph.gd",
    "res://tests/unit/test_celestial_motion.gd",
    "res://tests/unit/test_partition_address_v2.gd",
    "res://tests/unit/test_cube_sphere_grid.gd",
    "res://tests/unit/test_partition_foundation.gd",
    "res://tests/unit/test_atmosphere_layer.gd",
    "res://tests/unit/test_earth_generation_pipeline.gd",
    "res://tests/integration/test_controller_profiles.gd",
    "res://tests/integration/test_entity_registry_migration.gd",
    "res://tests/integration/test_first_person_interaction.gd",
    "res://tests/integration/test_persistence_roundtrip.gd",
    "res://tests/integration/test_terrain_streaming_contract.gd",
    "res://tests/items/test_item_domain.gd",
    "res://tests/items/test_item_lab_integration.gd",
    "res://tests/integration/test_unified_planetary_runtime.gd",
    "res://tests/integration/test_unified_runtime_boot.gd",
    "res://tests/runtime/test_world_boot_matrix.gd"
)

foreach ($TestScript in $Tests) {
    Write-Host "Running $TestScript"
    & $Godot --headless --path $ProjectRoot --script $TestScript
    if ($LASTEXITCODE -ne 0) {
        throw "Regression test failed: $TestScript"
    }
}

Write-Host "Running main-scene CLI test contract"
& $Godot --headless --path $ProjectRoot -- --world=playground --run-tests=all
if ($LASTEXITCODE -ne 0) {
    throw "Main-scene CLI regression suite failed."
}

Write-Host "All world/core regression tests passed."
