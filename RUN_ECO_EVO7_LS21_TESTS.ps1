param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
$Actual = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 LS2.1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$Tests = @(
    "res://tests/ecology/eco_evo7_live_world_shadow_acceptance.gd",
    "res://tests/ecology/eco_evo7_live_world_shadow_runtime_smoke.gd",
    "res://tests/ecology/eco_evo7_ls1_live_shadow_session_acceptance.gd",
    "res://tests/ecology/eco_evo7_ls2_live_polygon_acceptance.gd",
    "res://tests/ecology/eco_evo7_ls21_divergence_acceptance.gd"
)

foreach ($Test in $Tests) {
    Write-Host "=== $Test ==="
    & $GodotPath --headless --path $RootDir --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "ECO.EVO7 LS2.1 test failed: $Test exit=$LASTEXITCODE"
    }
}

Write-Host "ECO.EVO7 LS2.1 full predecessor + measurement runner: PASS"
