param(
    [switch]$NoFetch,
    [switch]$NoFailOnRed,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Auditor = Join-Path $ProjectRoot "scripts\control\project_control.py"
$DirectionalAuditor = Join-Path $ProjectRoot "scripts\control\project_control_directional_watch.py"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\control"
$BaseReport = Join-Path $ArtifactRoot "project-control-report.json"
$DirectionalReport = Join-Path $ArtifactRoot "directional-watch-report.json"

foreach ($RequiredAuditor in @($Auditor, $DirectionalAuditor)) {
    if (-not (Test-Path $RequiredAuditor)) {
        throw "PC0 auditor not found: $RequiredAuditor"
    }
}

# Always ask the Python auditors to emit reports without converting project RED
# into a process failure. This wrapper combines both reports and owns the final
# blocking/non-blocking exit policy.
$baseArgs = @($Auditor, "--no-fail-on-red")
if ($NoFetch) { $baseArgs += "--no-fetch" }
$directionalArgs = @($DirectionalAuditor, "--no-fail-on-red")

Write-Host "Distributed World Simulator - Project Control"
Write-Host "Root: $ProjectRoot"
Write-Host "Auditor: $Auditor"
Write-Host "Directional watch: $DirectionalAuditor"

& $Python @baseArgs
$baseExitCode = $LASTEXITCODE
if ($baseExitCode -ne 0) {
    Write-Host "PROJECT CONTROL: base auditor failed with exit code $baseExitCode"
    exit $baseExitCode
}

& $Python @directionalArgs
$directionalExitCode = $LASTEXITCODE
if ($directionalExitCode -ne 0) {
    Write-Host "PROJECT CONTROL: directional auditor failed with exit code $directionalExitCode"
    exit $directionalExitCode
}

foreach ($RequiredReport in @($BaseReport, $DirectionalReport)) {
    if (-not (Test-Path $RequiredReport)) {
        throw "PC0 report not found after audit: $RequiredReport"
    }
}

$baseHealth = (Get-Content -Raw -Path $BaseReport | ConvertFrom-Json).overall_health
$directionalHealth = (Get-Content -Raw -Path $DirectionalReport | ConvertFrom-Json).overall_health
$red = ($baseHealth -eq "RED") -or ($directionalHealth -eq "RED")

Write-Host "Combined health: base=$baseHealth directional=$directionalHealth"

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
