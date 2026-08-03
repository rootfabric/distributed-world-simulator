param([string]$GodotPath = "godot")
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c19_agent_automation_contracts.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c19_agent_automation_integration.gd
exit $LASTEXITCODE
