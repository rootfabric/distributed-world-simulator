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

& "$PSScriptRoot\RUN_T1B2_COMMAND_FAILURE_TESTS.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "T1B.2 accepted parent focused regression failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $PSScriptRoot --script res://tests/construction/t1b3_recovery_reconnect_composition_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "T1B.3 recovery/reconnect composition failed: $LASTEXITCODE"
}

Write-Host "T1B.3 recovery/reconnect composition focused gate passed."
