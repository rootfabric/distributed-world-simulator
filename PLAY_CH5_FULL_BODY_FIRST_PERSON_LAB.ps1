param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Runner = Join-Path $PSScriptRoot "PLAY_CH4_QUATERNIUS_CHARACTER_LAB.ps1"
if (-not (Test-Path $Runner)) {
    throw "CH4 character lab runner is missing: $Runner"
}

& $Runner -GodotPath $GodotPath
exit $LASTEXITCODE
