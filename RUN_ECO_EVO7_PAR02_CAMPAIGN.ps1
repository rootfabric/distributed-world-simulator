param(
    [string]$GodotBin = $env:GODOT_BIN,
    [int]$Generations = 12,
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
    throw "ECO.EVO7 PAR0.2 CAMPAIGN BLOCKED: expected Godot '$Expected', got '$Actual'"
}
# Fresh coordinator process per run; one persistent pool per dual process.
if ([string]::IsNullOrWhiteSpace($env:ECO_PAR0_WORKER_LOG_DIR)) {
    $env:ECO_PAR0_WORKER_LOG_DIR = Join-Path $Root 'artifacts/par0_worker_logs'
}
$env:ECO_PAR02_SESSION_ROOT = Join-Path $Root 'artifacts/par02_sessions'
$ArtifactDir = Join-Path $Root 'artifacts/par02'
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
$BaseSha = (& git -C $Root rev-parse HEAD).Trim()
$env:ECO_PAR02_BASE_SHA = $BaseSha
$env:ECO_PAR02_CANDIDATE_SHA = ''
$env:ECO_PAR02_GENERATIONS = "$Generations"

$Recipes = @('MIXED_PHYSICAL_HETEROGENEITY', 'WATER_GRADIENT_STRONG', 'RELIEF_DRAINAGE_STRONG')
$WorkerCounts = @(1, 2, 4)

function Invoke-Run([string]$Mode, [string]$Recipe, [int]$Workers, [string]$Artifact, [string]$Baseline = '') {
    $env:ECO_PAR02_MODE = $Mode
    $env:ECO_PAR02_RECIPE = $Recipe
    $env:ECO_PAR02_WORKERS = "$Workers"
    $env:ECO_PAR02_ARTIFACT = $Artifact
    $env:ECO_PAR02_BASELINE_ARTIFACT = $Baseline
    if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
        & $GodotBin --headless --path $Root --script 'res://scripts/ecology/perf/eco_evo7_par02_dual_campaign_runner_v1.gd' 2>$null
    } else {
        & $GodotBin --headless --path $Root --log-file $EngineLogFile --script 'res://scripts/ecology/perf/eco_evo7_par02_dual_campaign_runner_v1.gd' 2>$null
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# 1) Serial baselines: one fresh process per recipe, no executor, no pool.
foreach ($Recipe in $Recipes) {
    $serialArtifact = Join-Path $ArtifactDir ("serial_{0}.json" -f $Recipe.ToLower())
    Invoke-Run 'serial' $Recipe 0 $serialArtifact
}

# 2) Dual canonical runs: fresh process per recipe/wc, one persistent pool,
#    12 verified generations each (3 x 3 x 12 = 108 comparisons).
foreach ($Recipe in $Recipes) {
    $serialArtifact = Join-Path $ArtifactDir ("serial_{0}.json" -f $Recipe.ToLower())
    foreach ($Workers in $WorkerCounts) {
        $dualArtifact = Join-Path $ArtifactDir ("dual_{0}_wc{1}.json" -f $Recipe.ToLower(), $Workers)
        Invoke-Run 'dual' $Recipe $Workers $dualArtifact $serialArtifact
    }
}

# 3) Hash matrix + summary aggregation (fresh process).
$env:ECO_PAR02_MODE = ''
$Matrix = 'res://scripts/ecology/perf/eco_evo7_par02_campaign_matrix_v1.gd'
if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
    & $GodotBin --headless --path $Root --script $Matrix 2>$null
} else {
    & $GodotBin --headless --path $Root --log-file $EngineLogFile --script $Matrix 2>$null
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
