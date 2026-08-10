param(
    [switch]$NoFetch,
    [switch]$NoFailOnRed,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempDir = Join-Path $ProjectRoot "scripts\control"
$TempAuditor = Join-Path $TempDir ".pc0_main_runtime.py"

if (-not $NoFetch) {
    git -C $ProjectRoot fetch origin --prune
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed: $LASTEXITCODE" }
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
try {
    $source = git -C $ProjectRoot show origin/main:scripts/control/project_control.py
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($source -join "`n"))) {
        throw "PC0 auditor is not available in origin/main. Pull/fetch main after PC0 integration."
    }
    [IO.File]::WriteAllText($TempAuditor, ($source -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    $argsList = @($TempAuditor, "--no-fetch")
    if ($NoFailOnRed) { $argsList += "--no-fail-on-red" }
    & $Python @argsList
    $code = $LASTEXITCODE
    if ($code -eq 2) { Write-Host "PROJECT CONTROL: RED - next declared major stage is blocked." }
    exit $code
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $TempAuditor
}
