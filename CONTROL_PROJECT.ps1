param(
    [switch]$NoFetch,
    [switch]$NoFailOnRed,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Auditor = Join-Path $ProjectRoot "scripts\control\project_control.py"
$DirectionalAuditor = Join-Path $ProjectRoot "scripts\control\project_control_directional_watch.py"

foreach ($RequiredAuditor in @($Auditor, $DirectionalAuditor)) {
    if (-not (Test-Path $RequiredAuditor)) {
        throw "PC0 auditor not found: $RequiredAuditor"
    }
}

$baseArgs = @($Auditor)
if ($NoFetch) { $baseArgs += "--no-fetch" }
if ($NoFailOnRed) { $baseArgs += "--no-fail-on-red" }

$directionalArgs = @($DirectionalAuditor)
if ($NoFailOnRed) { $directionalArgs += "--no-fail-on-red" }

Write-Host "Distributed World Simulator - Project Control"
Write-Host "Root: $ProjectRoot"
Write-Host "Auditor: $Auditor"
Write-Host "Directional watch: $DirectionalAuditor"

& $Python @baseArgs
$baseExitCode = $LASTEXITCODE

if ($baseExitCode -notin @(0, 2)) {
    Write-Host "PROJECT CONTROL: base auditor failed with exit code $baseExitCode"
    exit $baseExitCode
}

& $Python @directionalArgs
$directionalExitCode = $LASTEXITCODE

if ($directionalExitCode -notin @(0, 2)) {
    Write-Host "PROJECT CONTROL: directional auditor failed with exit code $directionalExitCode"
    exit $directionalExitCode
}

$red = ($baseExitCode -eq 2) -or ($directionalExitCode -eq 2)

if ($red -and -not $NoFailOnRed) {
    Write-Host "PROJECT CONTROL: RED - next declared major stage is blocked."
    exit 2
}

if ($red) {
    Write-Host "PROJECT CONTROL: RED reported, non-blocking mode requested."
} else {
    Write-Host "PROJECT CONTROL: completed."
}

exit 0
