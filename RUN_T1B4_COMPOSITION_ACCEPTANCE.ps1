param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath is required. Pass -GodotPath or set GODOT_BIN."
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}

& "$PSScriptRoot\RUN_T1B3_RECOVERY_RECONNECT_TESTS.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "T1B.3 accepted parent focused regression failed: $LASTEXITCODE"
}

& $GodotPath --headless --editor --path $PSScriptRoot --quit
if ($LASTEXITCODE -ne 0) {
    throw "T1B.4 editor parse/import failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $PSScriptRoot --script res://tests/construction/t1b4_m3_failure_recovery_composition_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "T1B.4 live M3 failure/recovery composition failed: $LASTEXITCODE"
}

Write-Host "T1B.4 composition focused gate passed."
