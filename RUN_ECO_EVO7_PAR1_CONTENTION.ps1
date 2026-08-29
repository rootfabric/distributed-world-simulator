param(
    [string]$GodotBin = $env:GODOT_BIN,
    [int]$Seconds = 200
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
    throw "ECO.EVO7 PAR1 CONTENTION BLOCKED: expected Godot '$Expected', got '$Actual'"
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}
$env:GODOT_BIN = $GodotBin
# PAR1 graphical contention: the selected backend runs recruitment while the
# real PLAY0 scene evolves with AUTO evolution for >=3 minutes. Runs WITH a
# rendering window (FPS is meaningless headless).
$ErrorActionPreference = 'Continue'
& $GodotBin --path $Root --script res://tests/ecology/eco_evo7_par1_play0_contention.gd 2>$null
exit $LASTEXITCODE
