param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedIdentity = "4.7.1.stable.double.custom_build.a13da4feb"

function Resolve-Godot {
    param([string]$ExplicitPath)
    $candidates = @()
    if ($ExplicitPath) { $candidates += $ExplicitPath }
    if ($env:GODOT4_BIN) { $candidates += $env:GODOT4_BIN }
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
    $candidates += @(
        (Join-Path $Root "godot.linuxbsd.editor.double.x86_64"),
        (Join-Path $Root "godot.windows.editor.double.x86_64.exe"),
        (Join-Path $Root "godot.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $command = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Godot executable not found. Pass -GodotPath or set GODOT4_BIN."
}

$Godot = Resolve-Godot $GodotPath
$Identity = (& $Godot --version 2>&1 | Select-Object -First 1).Trim()
if ($Identity -ne $ExpectedIdentity) {
    throw "Wrong Godot identity: '$Identity'; expected '$ExpectedIdentity'."
}

$Tests = @(
    "res://tests/research/ecology/test_eco_vis2_1_control_branch_runner.gd",
    "res://tests/research/ecology/test_eco_vis2_1_treatment_branch_runner.gd",
    "res://tests/research/ecology/test_eco_vis2_1_comparison_model.gd",
    "res://tests/research/ecology/test_eco_vis1_8b_continuous_population_field.gd",
    "res://tests/research/ecology/test_eco_vis1_9_evolution_observatory.gd",
    "res://tests/research/ecology/test_eco_vis2_0_evolution_experiment_lab.gd",
    "res://tests/research/ecology/test_eco_vis2_1_control_vs_treatment_lab.gd"
)

Write-Host "ECO VIS2.1 gate"
Write-Host "Godot: $Identity"
Write-Host "Root:  $Root"

foreach ($Test in $Tests) {
    Write-Host "`n=== $Test ==="
    & $Godot --headless --path $Root --script $Test
    if ($LASTEXITCODE -ne 0) {
        throw "FAILED: $Test (exit $LASTEXITCODE)"
    }
}
Write-Host "`nECO VIS2.1 gate: PASS ($($Tests.Count) scripts)"
