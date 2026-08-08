param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Runner = Join-Path $PSScriptRoot "PLAY_CH5_FULL_BODY_FIRST_PERSON_LAB.ps1"
if (-not (Test-Path $Runner)) {
    throw "CH5/CH6 presentation lab runner is missing: $Runner"
}

& $Runner -GodotPath $GodotPath
exit $LASTEXITCODE
