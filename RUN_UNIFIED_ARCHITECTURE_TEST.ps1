$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RegressionRunner = Join-Path $ProjectRoot "RUN_WORLD_REGRESSION_TESTS.ps1"

if (-not (Test-Path $RegressionRunner)) {
    throw "Regression runner was not found: $RegressionRunner"
}

& $RegressionRunner
if ($LASTEXITCODE -ne 0) {
    throw "Unified simulator regression suite failed."
}
