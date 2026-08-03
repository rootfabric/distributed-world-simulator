param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "C23 editor parse failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c23_production_hardening_contracts.gd
if ($LASTEXITCODE -ne 0) { throw "C23 contracts failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c23_production_hardening_integration.gd
if ($LASTEXITCODE -ne 0) { throw "C23 integration failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c23_production_hardening_chaos.gd
if ($LASTEXITCODE -ne 0) { throw "C23 chaos failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c23_production_hardening_soak.gd
if ($LASTEXITCODE -ne 0) { throw "C23 soak failed: $LASTEXITCODE" }
