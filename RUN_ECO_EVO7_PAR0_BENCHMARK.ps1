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
# PAR0.1 benchmark: full shadow campaign — serial oracle baseline plus the
# persistent process pool at worker_count 1/2/4 across the three deterministic
# environment recipes, with byte-exact hash parity enforced every generation
# and per-generation timing capture (serial vs parallel recruitment).
# Set ECO_PAR0_GENERATIONS / ECO_PAR0_WORKERS / ECO_PAR0_RECIPES to override.
$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
    & $GodotBin --headless --path $Root --script res://scripts/ecology/perf/eco_evo7_par0_shadow_runner_v1.gd 2>$null
} else {
    & $GodotBin --headless --path $Root --log-file $EngineLogFile --script res://scripts/ecology/perf/eco_evo7_par0_shadow_runner_v1.gd 2>$null
}
exit $LASTEXITCODE