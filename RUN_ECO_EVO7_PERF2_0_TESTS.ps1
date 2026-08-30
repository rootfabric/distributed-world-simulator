param(
    [Alias('GodotPath')]
    [string]$GodotBin = $env:GODOT_BIN
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = '4.7.1.stable.double.custom_build.a13da4feb'

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    throw 'Set GODOT_BIN or pass -GodotBin with the exact double Godot 4.7.1 executable.'
}

$Actual = (& $GodotBin --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) {
    throw "ECO.EVO7 PERF2.0 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

$LogRoot = Join-Path $Root 'artifacts\perf2_gate_logs'
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$Tests = @(
    @{ Name = 'PERF1';   Script = 'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd' },
    @{ Name = 'STREAM1'; Script = 'res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd' },
    @{ Name = 'PERF2.0'; Script = 'res://tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd' }
)

foreach ($Entry in $Tests) {
    $Log = Join-Path $LogRoot (($Entry.Name -replace '\.','_') + '.log')
    Write-Host "PERF2.0 GATE START $($Entry.Name)"
    & $GodotBin --headless --path $Root --log-file $Log --script $Entry.Script
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PERF2.0 GATE FAIL $($Entry.Name) log=$Log"
        exit $LASTEXITCODE
    }
    Write-Host "PERF2.0 GATE PASS $($Entry.Name)"
}

Write-Host 'ECO.EVO7 PERF2.0 transitive measurement-contract acceptance: PASS'
exit 0
