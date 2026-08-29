param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$EngineLogFile = $env:ECO_PAR0_ENGINE_LOG
)
$ErrorActionPreference = 'Stop'
# Godot prints benign diagnostics (certificate store probe) to stderr; keep
# native stderr from aborting the runner under PowerShell 7.4+ policy.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PAR1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}
# PAR1 R1: inherited PAR0.2 gates run FIRST (fresh processes, serial default,
# no pool can spawn), then the focused PAR1 backend-selection acceptance:
# direct process backend exactness, WorkerThreadPool backend exactness,
# >=108 canonical generation comparisons across 3 recipes x wc 1/2/4 x 12
# generations, fixture-level exact parity for both backends vs the serial
# kernel on the SAME immutable input, and fail-closed fault injections.
$Tests = @(
    'res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd',
    'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd',
    'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd',
    'res://tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd',
    'res://tests/ecology/eco_evo7_par02_dual_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_par1_backend_selection_acceptance.gd'
)
$ErrorActionPreference = 'Continue'
foreach ($Test in $Tests) {
    if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
        & $GodotBin --headless --path $Root --script $Test 2>$null
    } else {
        & $GodotBin --headless --path $Root --log-file $EngineLogFile --script $Test 2>$null
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
