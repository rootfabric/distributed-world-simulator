param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "c11-local-geometry-editing-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

$Tests = @(
    "res://tests/construction/test_c11_local_geometry_editing_contracts.gd",
    "res://tests/construction/test_c11_local_geometry_editing_integration.gd"
)

$Steps = @()
$Passed = $false
try {
    $Started = [DateTime]::UtcNow
    & $GodotPath --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "C11 editor parse failed" }
    $Steps += [ordered]@{
        name = "editor_import_parse"
        passed = $true
        duration_seconds = ([DateTime]::UtcNow - $Started).TotalSeconds
    }

    foreach ($Test in $Tests) {
        $Started = [DateTime]::UtcNow
        & $GodotPath --headless --path $ProjectRoot --script $Test
        if ($LASTEXITCODE -ne 0) { throw "C11 test failed: $Test" }
        $Steps += [ordered]@{
            name = [IO.Path]::GetFileNameWithoutExtension($Test)
            target = $Test
            passed = $true
            duration_seconds = ([DateTime]::UtcNow - $Started).TotalSeconds
        }
    }
    $Passed = $true
}
finally {
    [ordered]@{
        schema = "planet_simulator.c11_local_geometry_editing_summary.v1"
        checkpoint = "C11_LOCAL_GEOMETRY_EDITING"
        passed = $Passed
        declared_test_count = $Tests.Count
        steps = $Steps
        finished_at_utc = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
}

if (-not $Passed) { exit 1 }
Write-Host "C11 Local Geometry Editing profile passed."
Write-Host "Report: $ReportPath"
