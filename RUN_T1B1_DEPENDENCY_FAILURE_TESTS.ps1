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

& "$PSScriptRoot\RUN_T1B0_RUNTIME_FAILURE_TESTS.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "T1B.0 accepted parent focused regression failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $PSScriptRoot --script res://tests/construction/t1b1_dependency_failure_propagation_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "T1B.1 dependency failure propagation failed: $LASTEXITCODE"
}

Write-Host "T1B.1 dependency failure propagation focused gate passed."
