param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "C21 editor parse failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c21_large_scale_acceptance_contracts.gd
if ($LASTEXITCODE -ne 0) { throw "C21 contracts failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c21_large_scale_acceptance_integration.gd
if ($LASTEXITCODE -ne 0) { throw "C21 integration failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c21_large_scale_acceptance_soak.gd
if ($LASTEXITCODE -ne 0) { throw "C21 soak failed: $LASTEXITCODE" }
