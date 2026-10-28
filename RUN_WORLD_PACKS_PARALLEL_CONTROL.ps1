param(
    [ValidateSet("status", "next", "instructions", "verify")]
    [string]$Action = "status",
    [string]$Track = "",
    [switch]$NoFetch,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Controller = Join-Path $RepoRoot "tools/world_packs/parallel_controller.py"

if ($env:PYTHON_BIN) {
    $Python = $env:PYTHON_BIN
} else {
    $PythonCommand = Get-Command python -ErrorAction Stop
    $Python = $PythonCommand.Source
}

$Arguments = @($Controller, $Action)
if ($Action -in @("instructions", "verify")) {
    if ([string]::IsNullOrWhiteSpace($Track)) {
        throw "-Track is required for $Action"
    }
    $Arguments += $Track
}
if ($NoFetch) {
    $Arguments += "--no-fetch"
}
if ($Json) {
    if ($Action -notin @("status", "next")) {
        throw "-Json is supported only for status/next"
    }
    $Arguments += "--json"
}

Push-Location $RepoRoot
try {
    & $Python @Arguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
