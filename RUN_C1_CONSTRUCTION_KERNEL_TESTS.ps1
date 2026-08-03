param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

& $GodotPath --headless --editor --path $ProjectRoot --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Tests = @(
    "res://tests/construction/test_c1_construction_contracts.gd",
    "res://tests/construction/test_c1_construct_aggregate.gd"
)

foreach ($Test in $Tests) {
    & $GodotPath --headless --path $ProjectRoot --script $Test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
