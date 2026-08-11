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

& "$PSScriptRoot\RUN_T1A7_5_COMPOSITION_TESTS.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    throw "T1A.7 accepted parent focused regression failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $PSScriptRoot --script res://tests/construction/t1b0_runtime_failure_contracts.gd
if ($LASTEXITCODE -ne 0) {
    throw "T1B.0 runtime failure contracts failed: $LASTEXITCODE"
}

Write-Host "T1B.0 runtime failure focused gate passed."
