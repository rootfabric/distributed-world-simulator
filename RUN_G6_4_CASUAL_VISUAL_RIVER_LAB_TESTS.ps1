param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath is required. Pass -GodotPath or set GODOT_BIN."
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "=== G6.3 accepted dependency gate ==="
& "$PSScriptRoot\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "G6.3 accepted dependency gate failed"
}

Write-Host "=== G6.4 source / P0 contract gate ==="
& $GodotPath --headless --path $PSScriptRoot --script res://tests/procedural/hydrology/g6_4_casual_visual_river_lab_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "G6.4 visual river lab contract gate failed"
}

Write-Host "=== G6.4 headless scene smoke ==="
& $GodotPath --headless --path $PSScriptRoot res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
if ($LASTEXITCODE -ne 0) {
    throw "G6.4 visual river lab headless smoke failed"
}

Write-Host "G6.4 Casual Visual River Lab automated gate passed."
Write-Host "Manual graphical observation is still required before G6.4 acceptance."
exit 0
