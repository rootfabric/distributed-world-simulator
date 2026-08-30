param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$EngineLogFile = $env:ECO_STREAM1_ENGINE_LOG
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
    throw "ECO.EVO7 STREAM1 BLOCKED: expected Godot '$Expected', got '$Actual'"
}

if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_SESSION_ROOT)) {
    $env:ECO_PAR0_SESSION_ROOT = Join-Path $Root 'artifacts/par0_sessions'
}

# STREAM1 is cut from PAR3 R3.2. Run the transitive parallel/runtime gates
# plus the new proposal/authority acceptance. Any non-zero test exits
# immediately; no later test can mask an earlier failure.
$Tests = @(
    'res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd',
    'res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd',
    'res://tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd',
    'res://tests/ecology/eco_evo7_par02_dual_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_par1_backend_selection_acceptance.gd',
    'res://tests/ecology/eco_evo7_par2_parallel_only_recruitment_acceptance.gd',
    'res://tests/ecology/eco_evo7_par3_parallel_candidate_reproduction_acceptance.gd',
    'res://tests/ecology/eco_evo7_stream1_generation_stream_acceptance.gd',
    'res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd',
    'res://tests/ecology/eco_evo7_play0_live_planet_playground_acceptance.gd'
)

$LogDir = Join-Path $Root 'artifacts/stream1_gate_logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$ErrorActionPreference = 'Continue'
foreach ($Test in $Tests) {
    Write-Host "=== STREAM1 gate: $Test ==="
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Test)
    $PerTestLog = if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
        Join-Path $LogDir "$BaseName.log"
    } else {
        $EngineLogFile
    }

    & $GodotBin --headless --path $Root --log-file $PerTestLog --script $Test
    if ($LASTEXITCODE -ne 0) {
        Write-Error "STREAM1 gate failed: $Test (exit=$LASTEXITCODE, log=$PerTestLog)"
        exit $LASTEXITCODE
    }
}

Write-Host "STREAM1 logs: $LogDir"
Write-Host 'ECO.EVO7 STREAM1 transitive acceptance: PASS'
exit 0
