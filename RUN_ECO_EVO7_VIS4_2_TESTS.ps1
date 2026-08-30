param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$GitHead = (& git -C $RootDir rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($GitHead)) {
    throw "Unable to resolve VIS4.2 Git HEAD"
}
Write-Host "ECO.EVO7 VIS4.2 git_head=$GitHead"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 VIS4.2 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    $UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        & $GodotPath --headless --editor --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import failed with exit code $LASTEXITCODE"
        }
    }

    & (Join-Path $RootDir "RUN_ECO_EVO7_VIS4_1_TESTS.ps1") -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) {
        throw "VIS4.1 R2 predecessor regression failed"
    }

    Write-Host "=== ECO VIS3 presentation regression ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "VIS3 presentation regression failed with exit code $LASTEXITCODE"
    }

    Write-Host "=== ECO VIS4.2 honest diagnostic morphology ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/ecology/eco_evo7_vis4_2_honest_diagnostic_morphology_acceptance.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "VIS4.2 focused acceptance failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}

Write-Host "ECO.EVO7 VIS4.2 Honest Diagnostic Morphology candidate: PASS"
