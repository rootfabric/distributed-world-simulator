$ErrorActionPreference = "Stop"

$DefaultLog = Join-Path $env:APPDATA "Godot\app_userdata\Real Scale Procedural Moon\logs\terrain_performance.jsonl"
$LogPath = if ($args.Count -gt 0) { $args[0] } else { $DefaultLog }

if (-not (Test-Path $LogPath)) {
    throw "Terrain performance log was not found: $LogPath"
}

$Rows = @()
Get-Content $LogPath | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
        $Entry = $_ | ConvertFrom-Json
    } catch {
        return
    }
    if ($Entry.event -ne "earth_surface_rebuild") { return }

    $Mesh = $Entry.data.mesh
    $Terrain = $Entry.data.terrain
    $Placement = $Entry.data.placement
    $Rows += [PSCustomObject]@{
        Time = $Entry.timestamp_utc
        Biome = [string]$Entry.data.biome
        TotalMs = [Math]::Round([double]$Entry.data.elapsed_ms, 2)
        PipelineMs = [Math]::Round([double]$Terrain.last_batch_elapsed_ms, 2)
        TerrainSamples = [int]$Terrain.last_batch_sample_count
        PlacementSamples = [int]$Placement.pipeline_samples
        MinM = [Math]::Round([double]$Mesh.minimum_elevation_m, 1)
        MaxM = [Math]::Round([double]$Mesh.maximum_elevation_m, 1)
        ReliefM = [Math]::Round([double]$Mesh.relief_range_m, 1)
        AvgSlope = [Math]::Round([double]$Mesh.average_geometric_slope_deg, 1)
        MaxSlope = [Math]::Round([double]$Mesh.maximum_geometric_slope_deg, 1)
        Trees = [int]$Placement.near_trees + [int]$Placement.billboard_trees
        Grass = [int]$Placement.grass
        Rocks = [int]$Placement.rocks
    }
}

if ($Rows.Count -eq 0) {
    Write-Host "No earth_surface_rebuild entries were found. Enter shared-space mode with P and visit Earth with key 7."
    exit 0
}

Write-Host ""
Write-Host "=== Procedural Earth surface rebuilds ==="
Write-Host "Log: $LogPath"
$Rows | Select-Object -Last 25 | Format-Table -AutoSize

$Relief = @($Rows | ForEach-Object { [double]$_.ReliefM })
$Total = @($Rows | ForEach-Object { [double]$_.TotalMs })
Write-Host ""
Write-Host ("Rebuilds: {0}; average relief: {1:N1} m; maximum relief: {2:N1} m; average rebuild: {3:N2} ms; maximum rebuild: {4:N2} ms" -f `
    $Rows.Count,
    ($Relief | Measure-Object -Average).Average,
    ($Relief | Measure-Object -Maximum).Maximum,
    ($Total | Measure-Object -Average).Average,
    ($Total | Measure-Object -Maximum).Maximum
)
