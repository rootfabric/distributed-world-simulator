$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$UserDataRoot = Join-Path $env:APPDATA "Godot\app_userdata\Real Scale Procedural Moon"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Staging = Join-Path $env:TEMP "lunar-terrain-diagnostics-$Timestamp"
$Output = Join-Path $ProjectRoot "lunar-terrain-diagnostics-$Timestamp.zip"

if (-not (Test-Path $UserDataRoot)) {
    throw "Godot user data directory was not found: $UserDataRoot"
}

New-Item -ItemType Directory -Force -Path $Staging | Out-Null

$Paths = @(
    (Join-Path $UserDataRoot "logs\lunar_simulation.jsonl"),
    (Join-Path $UserDataRoot "logs\lunar_simulation.jsonl.1"),
    (Join-Path $UserDataRoot "logs\terrain_performance.jsonl"),
    (Join-Path $UserDataRoot "logs\terrain_performance.jsonl.1")
)

foreach ($Path in $Paths) {
    if (Test-Path $Path) {
        Copy-Item $Path $Staging
    }
}

$Diagnostics = Join-Path $UserDataRoot "diagnostics"
if (Test-Path $Diagnostics) {
    Copy-Item $Diagnostics (Join-Path $Staging "diagnostics") -Recurse
}

$StreamingConfig = Join-Path $ProjectRoot "config\terrain_streaming.json"
if (Test-Path $StreamingConfig) {
    Copy-Item $StreamingConfig $Staging
}

if (Test-Path $Output) {
    Remove-Item $Output -Force
}
Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $Output -CompressionLevel Optimal
Remove-Item $Staging -Recurse -Force

Write-Host "Terrain diagnostics archive created:"
Write-Host $Output
