param(
    [string]$GodotBin = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'
$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PERF1-PAR0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}
# PAR0 R1 benchmark is the deterministic serial-shadow run with kernel replay.
# Full multi-process pool campaign (worker_count 1/2/4 + mailbox + pipe) is
# deferred to PAR0.1 — see docs/checkpoints/PERF1_PAR0_RU.md for the
# PIPE_TRANSPORT_PARTIAL record and the deferred work package.
& $GodotBin --headless --path $Root --script res://scripts/ecology/perf/eco_evo7_par0_serial_shadow_v1.gd
exit $LASTEXITCODE