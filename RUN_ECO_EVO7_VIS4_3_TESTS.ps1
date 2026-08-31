param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$GitHead = (& git -C $RootDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($GitHead)) {
    throw "Unable to resolve VIS4.3 Git HEAD"
}
Write-Host "ECO.EVO7 VIS4.3 git_head=$GitHead"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS4.3 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
    }

    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_2_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { throw "VIS4.2 R2 predecessor regression failed" }

    $Ph5Tests = @(
        @{ Name="PH5 render-description regression"; Script="res://tests/research/ecology/eco_ph5_render_materialization_acceptance.gd" },
        @{ Name="PH5-S2 real 3D materialization regression"; Script="res://tests/research/ecology/eco_ph5_s2_3d_materialization_acceptance.gd" },
        @{ Name="PH5-S3 multiscale policy regression"; Script="res://tests/research/ecology/eco_ph5_s3_multiscale_acceptance.gd" },
        @{ Name="PH5-S3 multiscale materialization regression"; Script="res://tests/research/ecology/eco_ph5_s3_multiscale_materialization_acceptance.gd" },
        @{ Name="PH5-S4 representation robustness regression"; Script="res://tests/research/ecology/eco_ph5_s4_representation_robustness.gd" },
        @{ Name="PH5-S4 phenotype x tier matrix regression"; Script="res://tests/research/ecology/eco_ph5_s4_multiscale_matrix_acceptance.gd" }
    )
    foreach ($Test in $Ph5Tests) {
        Write-Host "=== ECO $($Test.Name) ==="
        & $GodotPath --headless --path $RootDir --script $Test.Script
        if ($LASTEXITCODE -ne 0) { throw "$($Test.Name) failed with exit code $LASTEXITCODE" }
    }

    Write-Host "=== ECO VIS4.3 exact Live Phenotype -> PH5 bridge ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_vis4_3_exact_ph5_bridge_acceptance.gd"
    if ($LASTEXITCODE -ne 0) { throw "VIS4.3 focused acceptance failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}

Write-Host "ECO.EVO7 VIS4.3 Exact Live Phenotype -> PH5 Bridge candidate: PASS"
