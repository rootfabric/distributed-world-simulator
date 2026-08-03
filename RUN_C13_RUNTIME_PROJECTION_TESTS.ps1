param(
    [string]$GodotPath = "godot"
)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c13_runtime_projection_contracts.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c13_runtime_projection_integration.gd
exit $LASTEXITCODE
