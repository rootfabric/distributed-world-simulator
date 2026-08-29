param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$EngineLogFile = $env:ECO_PAR0_ENGINE_LOG
)
$ErrorActionPreference = 'Stop'
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
    throw "ECO.EVO7 PAR2 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}
# PAR2 R1 regression: inherited PAR0.2 gates, PAR1 acceptance (backend
# selection stands), then the focused PAR2 acceptance (parallel-only
# recruitment + bounded deterministic audits + fail-closed injections),
# VIS3 and the PLAY0 playground gate. PLAY0 graphical contention with the
# PAR2 executor is covered by RUN_ECO_EVO7_PAR1_CONTENTION.ps1 semantics
# (same injection seam) and by the PLAY0 acceptance below.
$Tests = @(
    'res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd',
    'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd',
    'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd',
    'res://tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd',
    'res://tests/ecology/eco_evo7_par02_dual_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_par1_backend_selection_acceptance.gd',
    'res://tests/ecology/eco_evo7_par2_parallel_only_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_play0_live_planet_playground_acceptance.gd'
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
