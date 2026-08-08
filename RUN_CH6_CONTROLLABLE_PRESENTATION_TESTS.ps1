param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Runner = Join-Path $PSScriptRoot "RUN_CH5_FULL_BODY_FIRST_PERSON_TESTS.ps1"
if (-not (Test-Path $Runner)) {
    throw "CH5/CH6 presentation runner is missing: $Runner"
}

& $Runner -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "CH6 fix1 Shadow Preservation acceptance runner: PASS" -ForegroundColor Green
exit 0
