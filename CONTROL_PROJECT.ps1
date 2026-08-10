param(
    [switch]$NoFetch,
    [switch]$NoFailOnRed,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Auditor = Join-Path $ProjectRoot "scripts\control\project_control.py"

if (-not (Test-Path $Auditor)) {
    throw "PC0 auditor not found: $Auditor"
}

$argsList = @($Auditor)
if ($NoFetch) { $argsList += "--no-fetch" }
if ($NoFailOnRed) { $argsList += "--no-fail-on-red" }

Write-Host "Distributed World Simulator - Project Control"
Write-Host "Root: $ProjectRoot"
Write-Host "Auditor: $Auditor"

& $Python @argsList
$exitCode = $LASTEXITCODE

if ($exitCode -eq 2) {
    Write-Host "PROJECT CONTROL: RED - next declared major stage is blocked."
} elseif ($exitCode -eq 0) {
    Write-Host "PROJECT CONTROL: completed."
} else {
    Write-Host "PROJECT CONTROL: auditor failed with exit code $exitCode"
}

exit $exitCode
