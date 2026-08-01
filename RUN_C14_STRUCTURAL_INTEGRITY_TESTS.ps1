param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c14_structural_integrity_contracts.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $GodotPath --headless --path $ProjectRoot --script res://tests/construction/test_c14_structural_integrity_integration.gd
exit $LASTEXITCODE
