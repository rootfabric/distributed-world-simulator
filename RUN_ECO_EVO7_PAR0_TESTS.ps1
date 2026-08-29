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
    throw "ECO.EVO7 PERF1-PAR0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
# Workers must not write engine logs to user:// (unreliable in restricted
# environments); keep all PAR0 runtime state under artifacts/ (git-ignored).
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}
# PAR0 R1 inherits all PERF1 gates; the kernel refactor must not change
# observable behaviour, so the inherited counters stay green.
$Tests = @(
    'res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd',
    'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd',
    'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd',
    # PAR0 R1 dedicated gates: single-implementation + partition/merge
    # determinism, then the persistent-worker transport probe (HELLO/PING/
    # ECHO/QUIT lifecycle, 1/2/4 workers, timeout/crash/out-of-order).
    'res://tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd',
    'res://scripts/ecology/perf/eco_evo7_par0_transport_probe_v1.gd'
)
# Native Godot stderr diagnostics must not terminate the runner; pass/fail
# is decided by exit codes below.
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