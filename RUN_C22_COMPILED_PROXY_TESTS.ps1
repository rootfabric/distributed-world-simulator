param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "C22 editor parse failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c22_compiled_proxy_contracts.gd
if ($LASTEXITCODE -ne 0) { throw "C22 contracts failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c22_compiled_proxy_integration.gd
if ($LASTEXITCODE -ne 0) { throw "C22 integration failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c22_compiled_proxy_graphical.gd
if ($LASTEXITCODE -ne 0) { throw "C22 graphical failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c22_compiled_proxy_scale_soak.gd
if ($LASTEXITCODE -ne 0) { throw "C22 scale/soak failed: $LASTEXITCODE" }
