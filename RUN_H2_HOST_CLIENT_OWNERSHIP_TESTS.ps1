param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "godot" }
& $GodotPath --headless --editor --path $Root --quit; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $Root --script res://tests/runtime/test_h2_player_ownership_contracts.gd; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $Root --script res://tests/runtime/test_h2_host_client_processes.gd; exit $LASTEXITCODE
