param([Parameter(Mandatory=$false)][string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath or GODOT_BIN is required." }
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "C24 editor parse failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c24_proxy_mesh_backend_contracts.gd
if ($LASTEXITCODE -ne 0) { throw "C24 contracts failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c24_proxy_mesh_backend_integration.gd
if ($LASTEXITCODE -ne 0) { throw "C24 integration failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c24_proxy_mesh_backend_graphical.gd
if ($LASTEXITCODE -ne 0) { throw "C24 graphical failed: $LASTEXITCODE" }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c24_proxy_mesh_backend_scale_soak.gd
if ($LASTEXITCODE -ne 0) { throw "C24 scale/soak failed: $LASTEXITCODE" }
