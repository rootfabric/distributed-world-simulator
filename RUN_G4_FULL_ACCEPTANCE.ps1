$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$G3Runner = Join-Path $RootDir "RUN_G3_MACRO_SURFACE_TESTS.ps1"
$G4Runner = Join-Path $RootDir "RUN_G4_PROVIDER_COMPOSITION_TESTS.ps1"
$WorldRunner = Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1"
$RegressionArtifacts = Join-Path $RootDir "artifacts\test-results"
foreach ($RequiredPath in @($G3Runner, $G4Runner, $WorldRunner)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) { throw "Required G4 acceptance runner is missing: $RequiredPath" }
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

    Write-Host "=== G3 accepted dependency focused gate ==="
    & $G3Runner
    if (-not $?) { throw "G3 dependency focused gate failed." }

    Write-Host "=== G4 provider composition / replacement ==="
    & $G4Runner
    if (-not $?) { throw "G4 focused runner failed." }

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
    $BaseRef = "origin/docs/universal-world-generation-roadmap-post-g3"
    & git -C $RootDir rev-parse --verify $BaseRef *> $null
    if ($LASTEXITCODE -ne 0) { $BaseRef = "docs/universal-world-generation-roadmap-post-g3" }
    & git -C $RootDir diff --check "$BaseRef...HEAD"
    if ($LASTEXITCODE -ne 0) { throw "git diff --check failed against $BaseRef" }

    $ChangedFiles = @(& git -C $RootDir diff --name-only "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate G4 changed files against $BaseRef" }
    $FrozenPaths = @(
        "scripts/simulation/procedural/geo_kernel.gd",
        "scripts/simulation/procedural/contracts/surface_cell_key.gd",
        "scripts/simulation/procedural/surface/cube_sphere_addressing.gd",
        "scripts/simulation/procedural/surface/surface_lod_selector.gd",
        "scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd"
    )
    $FrozenChanges = @($ChangedFiles | Where-Object { $FrozenPaths -contains $_ })
    if ($FrozenChanges.Count -gt 0) { throw "G4 modified frozen G0-G3 architecture paths: $($FrozenChanges -join ', ')" }

    # The M5 graphical acceptance driver is test orchestration living under
    # scripts/runtime for historical reasons. Its convergence-shutdown barrier
    # was repaired while validating this branch, without changing production
    # gameplay/network semantics. Keep the production freeze strict for every
    # other runtime/network/Matter path.
    $AllowedAcceptanceHarnessChanges = @(
        "scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd"
    )
    $ProductionChanges = @($ChangedFiles | Where-Object {
        (
            $_ -like "scenes/worlds/*" -or
            $_ -like "scripts/runtime/*" -or
            $_ -like "scripts/network/*" -or
            $_ -like "scripts/simulation/matter/*"
        ) -and $AllowedAcceptanceHarnessChanges -notcontains $_
    })
    if ($ProductionChanges.Count -gt 0) { throw "G4 unexpectedly modified production/runtime paths: $($ProductionChanges -join ', ')" }
    $AllowedHarnessChanges = @($ChangedFiles | Where-Object { $AllowedAcceptanceHarnessChanges -contains $_ })
    if ($AllowedHarnessChanges.Count -gt 0) {
        Write-Host "Allowed acceptance-harness stabilization: $($AllowedHarnessChanges -join ', ')"
    }

    Write-Host "G4 full acceptance gate: PASS"
}
finally {
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
