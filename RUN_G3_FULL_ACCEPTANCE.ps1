$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G2Runner = Join-Path $RootDir "RUN_G2_PLANETARY_CELLS_TESTS.ps1"
$G3Runner = Join-Path $RootDir "RUN_G3_MACRO_SURFACE_TESTS.ps1"
$WorldRunner = Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1"
foreach ($RequiredPath in @($G2Runner,$G3Runner,$WorldRunner)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) { throw "Required G3 acceptance runner is missing: $RequiredPath" }
}
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
Write-Host "=== G2 dependency focused gate ==="
& $G2Runner
if (-not $?) { throw "G2 dependency focused gate failed." }
Write-Host "=== G3 focused macro surface ==="
& $G3Runner
if (-not $?) { throw "G3 focused runner failed." }
Write-Host "=== Full world/core regression ==="
& $WorldRunner
if (-not $?) { throw "World/core regression failed." }
Write-Host "=== Git diff hygiene ==="
$BaseRef = "origin/feature/g2-planetary-cells-lod"
& git -C $RootDir rev-parse --verify $BaseRef *> $null
if ($LASTEXITCODE -ne 0) { $BaseRef = "feature/g2-planetary-cells-lod" }
& git -C $RootDir diff --check "$BaseRef...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed against $BaseRef" }
Write-Host "G3 full acceptance gate: PASS"
