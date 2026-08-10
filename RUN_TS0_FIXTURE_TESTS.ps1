param(
    [Parameter(Mandatory=$false)]
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath or GODOT_BIN is required."
}

& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) {
    throw "TS0.0 editor import failed: $LASTEXITCODE"
}

& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/ts0/ts0_fixture_contract_acceptance.gd
if ($LASTEXITCODE -ne 0) {
    throw "TS0.0 fixture contract acceptance failed: $LASTEXITCODE"
}
