param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "T1A.0 editor parse failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_t1a0_complex_construct_demo_baseline.gd
if ($LASTEXITCODE -ne 0) { throw "T1A.0 baseline contracts failed: $LASTEXITCODE" }
Write-Host "T1A.0 complex construct demo baseline passed."
