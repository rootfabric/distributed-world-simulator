$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$LegacyPaths = @(
    "scripts/lod",
    "LOD_ARCHITECTURE_V9_RU.md",
    "LOD_LAYERS_V8_RU.md",
    "MICRO_DETAIL_ARCHITECTURE_RU.md",
    "PHOTO_SURFACE_V9_RU.md"
)

foreach ($LegacyPath in $LegacyPaths) {
    if (Test-Path $LegacyPath) {
        Remove-Item $LegacyPath -Recurse -Force
        Write-Host "Removed legacy path: $LegacyPath"
    }
}

if (Test-Path ".godot") {
    Remove-Item ".godot" -Recurse -Force
    Write-Host "Removed Godot import cache: .godot"
}

Write-Host "Migration to v11 directory layout is complete."
