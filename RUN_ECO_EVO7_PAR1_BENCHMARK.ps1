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
    throw "ECO.EVO7 PAR1 BENCHMARK BLOCKED: expected Godot '$Expected', got '$Actual'"
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}
# PAR1 benchmark: deterministic LS3.3-derived fixtures at parent counts
# 64/256/512/1024/2048 (fixture build excluded from timing), SERIAL vs
# PROCESS_POOL vs WORKER_THREAD_POOL at worker counts 1/2/4/8, 2 warmups +
# 7 measured iterations, p50/p95/min/max per stage and total, plus exact
# parity enforcement per fixture. Machine-readable summary is written to
# artifacts/par1_backend_benchmark.json and printed as PAR1_BENCHMARK_SUMMARY.
$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
    & $GodotBin --headless --path $Root --script res://scripts/ecology/perf/eco_evo7_par1_backend_benchmark_v1.gd 2>$null
} else {
    & $GodotBin --headless --path $Root --log-file $EngineLogFile --script res://scripts/ecology/perf/eco_evo7_par1_backend_benchmark_v1.gd 2>$null
}
exit $LASTEXITCODE
