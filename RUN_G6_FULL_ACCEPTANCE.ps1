$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G5Runner = Join-Path $RootDir "RUN_G5_WORLD_FEATURE_GRAPH_TESTS.ps1"
$G6Runner = Join-Path $RootDir "RUN_G6_HYDROLOGY_TESTS.ps1"
$WorldRunner = Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1"
$RegressionArtifacts = Join-Path $RootDir "artifacts\test-results"
foreach ($RequiredPath in @($G5Runner, $G6Runner, $WorldRunner)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) { throw "Required G6 acceptance runner is missing: $RequiredPath" }
}
$PowerShellExecutable = if ($PSVersionTable.PSEdition -eq "Core") { Join-Path $PSHOME "pwsh.exe" } else { Join-Path $PSHOME "powershell.exe" }
if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
    $PowerShellExecutable = (Get-Command powershell.exe, pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}
if ([string]::IsNullOrWhiteSpace($PowerShellExecutable)) { throw "PowerShell executable for isolated world regression was not found." }

$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G5 accepted dependency focused gate ==="
    & $G5Runner
    if (-not $?) { throw "G5 dependency focused gate failed." }

    Write-Host "=== G6 Hydrology / Fluid Surface v0 ==="
    & $G6Runner
    if (-not $?) { throw "G6 focused runner failed." }

    Write-Host "=== Full world/core regression ==="
    $RegressionStartedUtc = [DateTime]::UtcNow
    & $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $WorldRunner
    if ($LASTEXITCODE -ne 0) { throw "World/core regression failed with exit code $LASTEXITCODE" }

    Write-Host "=== Regression log-noise audit ==="
    $Pattern = "[breakpoint_runtime] could not listen on 127.0.0.1:9081"
    $Hits = @()
    if (Test-Path -LiteralPath $RegressionArtifacts -PathType Container) {
        $AuditFloorUtc = $RegressionStartedUtc.AddSeconds(-2)
        $Hits = @(Get-ChildItem -LiteralPath $RegressionArtifacts -Recurse -File -Filter "*.log" |
            Where-Object { $_.LastWriteTimeUtc -ge $AuditFloorUtc } | Select-String -SimpleMatch $Pattern)
    }
    if ($Hits.Count -gt 0) { throw "Breakpoint runtime :9081 collision noise remained in current regression logs ($($Hits.Count) hits)." }
    Write-Host "Breakpoint runtime :9081 collision noise: 0"

    Write-Host "=== Git diff hygiene / architecture freeze ==="
    $BaseRef = "origin/feature/g5-world-feature-graph"
    & git -C $RootDir rev-parse --verify $BaseRef *> $null
    if ($LASTEXITCODE -ne 0) { $BaseRef = "feature/g5-world-feature-graph" }
    & git -C $RootDir diff --check "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) { throw "git diff --check failed against $BaseRef" }

    $ChangedFiles = @(& git -C $RootDir diff --name-only "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate G6 changed files against $BaseRef" }
    $FrozenPaths = @(
        "scripts/simulation/procedural/geo_kernel.gd",
        "scripts/simulation/procedural/contracts/surface_cell_key.gd",
        "scripts/simulation/procedural/surface/cube_sphere_addressing.gd",
        "scripts/simulation/procedural/surface/surface_lod_selector.gd",
        "scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd",
        "scripts/simulation/procedural/composition/geo_provider_registry.gd",
        "scripts/simulation/procedural/composition/geo_recipe_composer.gd",
        "scripts/simulation/procedural/providers/base_surface_provider_v1.gd",
        "scripts/simulation/procedural/providers/casual_macro_terrain_layer_provider_v1.gd",
        "scripts/simulation/procedural/providers/alternative_macro_terrain_provider_v1.gd",
        "scripts/simulation/procedural/providers/casual_valley_modifier_provider_v1.gd",
        "scripts/simulation/procedural/contracts/feature_anchor.gd",
        "scripts/simulation/procedural/contracts/feature_bounds.gd",
        "scripts/simulation/procedural/contracts/feature_id.gd",
        "scripts/simulation/procedural/contracts/feature_query.gd",
        "scripts/simulation/procedural/contracts/feature_relation.gd",
        "scripts/simulation/procedural/contracts/feature_type.gd",
        "scripts/simulation/procedural/contracts/world_feature.gd",
        "scripts/simulation/procedural/features/feature_graph.gd"
    )
    $FrozenChanges = @($ChangedFiles | Where-Object { $FrozenPaths -contains $_ })
    if ($FrozenChanges.Count -gt 0) { throw "G6 modified frozen G0-G5 architecture paths: $($FrozenChanges -join ', ')" }
    $ProductionChanges = @($ChangedFiles | Where-Object {
        $_ -like "scenes/worlds/*" -or
        $_ -like "scripts/runtime/*" -or
        $_ -like "scripts/network/*" -or
        $_ -like "scripts/simulation/matter/*"
    })
    if ($ProductionChanges.Count -gt 0) { throw "G6 unexpectedly modified production/runtime paths: $($ProductionChanges -join ', ')" }

    Write-Host "G6 full acceptance gate: PASS"
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
