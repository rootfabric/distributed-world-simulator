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

$Tests = @(
    "res://tests/runtime/test_int0_project_uid_contracts.gd",
    "res://tests/runtime/test_int0_m3_replica_resync_composition.gd"
)

foreach ($Test in $Tests) {
    & $GodotPath --headless --path $ProjectRoot --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "INT0 RL3/MW10 composition contract failed: $Test ($LASTEXITCODE)"
    }
}

Write-Host "INT0 RL3/MW10 composition focused gate: PASS" -ForegroundColor Green
