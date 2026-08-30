param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$GitHead = (& git -C $RootDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($GitHead)) {
    throw "Unable to resolve VIS4.1 Git HEAD"
}
Write-Host "ECO.EVO7 VIS4.1 git_head=$GitHead"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS4.1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_0_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS4.0 parent audit regression failed" }

    $Tests = @(
        @{ Name="LS3.4 local competition regression"; Script="res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd" },
        @{ Name="LS3.6 Workbench regression"; Script="res://tests/ecology/eco_evo7_ls36_rule_workbench_acceptance.gd" },
        @{ Name="VIS4.1 source-bound morphology evidence"; Script="res://tests/ecology/eco_evo7_vis4_1_source_bound_morphology_evidence_acceptance.gd" }
    )
    foreach ($Test in $Tests) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) { throw "$($Test.Name) failed with exit code $LASTEXITCODE" }
    }

    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS2_TESTS.ps1") -GodotBin $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS2 presentation regression failed" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}
Write-Host "ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence candidate: PASS"
