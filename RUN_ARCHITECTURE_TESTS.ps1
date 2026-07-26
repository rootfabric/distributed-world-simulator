$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $ProjectRoot "RUN_COORDINATE_FOUNDATION_TESTS.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Architecture tests failed with exit code $LASTEXITCODE"
}
