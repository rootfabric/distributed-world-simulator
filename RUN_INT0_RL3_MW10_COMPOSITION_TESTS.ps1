param(
    [Parameter(Mandatory = $false)]
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath or GODOT_BIN is required."
}

& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) {
    throw "INT0 RL3/MW10 editor import failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $ProjectRoot --script `
    res://tests/runtime/test_int0_m3_replica_resync_composition.gd
if ($LASTEXITCODE -ne 0) {
    throw "INT0 RL3/MW10 M3 composition contracts failed: $LASTEXITCODE"
}

Write-Host "INT0 RL3/MW10 composition focused gate: PASS" -ForegroundColor Green
