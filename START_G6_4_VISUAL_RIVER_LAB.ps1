param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "G6.4 Casual Visual River Lab + G2 adaptive LOD + G3 macro surface"
Write-Host "Controls: A/D orbit, Q/E pitch, W/S zoom+refine/coarsen, Space auto-orbit, R reset"
Write-Host "Debug: 1 water, 2 centerline, 3 banks, 4 query probes, 5 seam markers, 6 LOD grid"
Write-Host "Watch refine: LOD grid shrinks while the actual macro terrain mesh gains triangles/detail"
Write-Host "River valley carving is intentionally deferred to G8 Geomorphology"

& $GodotPath --path $PSScriptRoot --scene "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn"
exit $LASTEXITCODE
