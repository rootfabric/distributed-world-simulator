$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$Godot   = $env:GODOT_BIN
if (-not $Godot) { $Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe' }
if (-not (Test-Path $Godot)) {
    Write-Error ("Godot binary not found: " + $Godot)
    exit 3
}

if (-not (Test-Path (Join-Path $repoRoot '.godot'))) {
    Write-Host ('[eg45-runner] running mandatory headless import pass before suites...')
    & $Godot --headless --editor --path $repoRoot --quit | Out-Null
}

$env:BREAKPOINT_RUNTIME_DISABLED = '1'

$tests = @(
    'tests/network/test_eg45_interaction_router.gd',
    'tests/network/test_eg45_scenarios.gd',
    'tests/network/test_eg45_zero_write_fence.gd'
)

$summary = [ordered]@{
    schema       = 'planet_simulator.eg45_edge_gateway_suite_summary.v1'
    started_at   = (Get-Date).ToString('o')
    runner       = 'RUN_EG45_EDGE_GATEWAY_TESTS.ps1'
    passed       = $true
    failure_markers = @()
    suites       = @()
    exit_code    = 0
}

foreach ($t in $tests) {
    Write-Host ('[eg45-runner] running ' + $t)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    & $Godot --headless --path $repoRoot --script $t 2>&1 | Tee-Object -FilePath $tmpOut | Out-Null
    $exit = $LASTEXITCODE
    $content = Get-Content -Raw $tmpOut
    Remove-Item $tmpOut -Force
    $markers = @()
    foreach ($m in @('][FAIL]', '"verdict": "FAIL"', 'SCRIPT ERROR:', 'PREDICATE_NOT_DEMONSTRATED')) {
        if ($content.Contains($m)) { $markers += $m }
    }
    $suiteObj = [ordered]@{
        name = $t
        exit_code = $exit
        passed = ($exit -eq 0) -and ($markers.Count -eq 0)
        markers = $markers
    }
    $summary.suites += $suiteObj
    if (-not $suiteObj.passed) {
        $summary.passed = $false
    }
}

$summary.finished_at = (Get-Date).ToString('o')

$artifactsDir = Join-Path $repoRoot 'artifacts/test-results'
if (-not (Test-Path $artifactsDir)) { New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null }
$tmpJson = Join-Path $artifactsDir ('.eg45-edge-gateway-summary.' + [guid]::NewGuid().ToString('N') + '.json')
$json = $summary | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tmpJson, $json, $utf8NoBom)
$finalJson = Join-Path $artifactsDir 'eg45-edge-gateway-summary.json'
Move-Item -Force $tmpJson $finalJson

if (-not $summary.passed) {
    $summary.exit_code = 1
    $jsonOut = $summary | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($finalJson, $jsonOut, $utf8NoBom)
    Write-Host ('[eg45-runner] FAILED: see ' + $finalJson)
    exit 1
}
Write-Host ('[eg45-runner] PASS: ' + $finalJson)
exit 0
