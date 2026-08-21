param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

function Invoke-GodotScript([string]$Label, [string]$ScriptPath) {
    Write-Host "=== $Label ==="
    $previous = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $output = & $GodotPath --headless --path $RootDir --script $ScriptPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previous) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
        else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
    }
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    return ($output -join "`n")
}

Write-Host "=== ECO CAL1-E accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_E_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-E accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO CAL1-F calibration + full-pool robustness" "res://tests/research/ecology/eco_cal1_f_full_pool_robustness_acceptance.gd"
$replayA = Invoke-GodotScript "ECO CAL1-F fresh process replay A" "res://tests/research/ecology/eco_cal1_f_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO CAL1-F fresh process replay B" "res://tests/research/ecology/eco_cal1_f_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$seedSignatures = [regex]::Match($acceptance, 'seed_signatures=([0-9]+)')
$seedMultiPareto = [regex]::Match($acceptance, 'seed_multi_pareto=([0-9.]+)')
$envPareto = [regex]::Match($acceptance, 'env_pareto_signatures=([0-9]+)')
$densityViolations = [regex]::Match($acceptance, 'density_violations=([0-9]+)')
$survivalViolations = [regex]::Match($acceptance, 'disturbance_survival_violations=([0-9]+)')
$seedViolations = [regex]::Match($acceptance, 'disturbance_seed_violations=([0-9]+)')
$minJaccard = [regex]::Match($acceptance, 'calibration_min_jaccard=([0-9.]+)')
$meanJaccard = [regex]::Match($acceptance, 'calibration_mean_jaccard=([0-9.]+)')
$pairwise = [regex]::Match($acceptance, 'pairwise_contradictions=([0-9]+)')
$classification = [regex]::Match($acceptance, 'classification=([A-Z0-9_]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $seedSignatures, $seedMultiPareto, $envPareto, $densityViolations, $survivalViolations, $seedViolations, $minJaccard, $meanJaccard, $pairwise, $classification)) {
    if (-not $m.Success) { throw "Unable to parse CAL1-F canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "CAL1-F fresh-process hash mismatch"
}
if ([int]$densityViolations.Groups[1].Value -ne 0 -or [int]$survivalViolations.Groups[1].Value -ne 0 -or [int]$seedViolations.Groups[1].Value -ne 0 -or [int]$pairwise.Groups[1].Value -ne 0) {
    throw "CAL1-F causal monotonicity / pairwise consistency violation"
}
if ($classification.Groups[1].Value -ne "ROBUST_UNITY_CALIBRATION") {
    throw "CAL1-F robustness classification is not accepted"
}

Write-Host "ECO.CAL1-E accepted regression: PASS"
Write-Host "ECO.CAL1-F calibration + full-pool robustness: PASS"
Write-Host "ECO.CAL1-F fresh-process replay: PASS"
Write-Host "ECO.CAL1-F aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.CAL1-F seed_signatures=$($seedSignatures.Groups[1].Value)"
Write-Host "ECO.CAL1-F seed_multi_pareto=$($seedMultiPareto.Groups[1].Value)"
Write-Host "ECO.CAL1-F env_pareto_signatures=$($envPareto.Groups[1].Value)"
Write-Host "ECO.CAL1-F density_violations=$($densityViolations.Groups[1].Value)"
Write-Host "ECO.CAL1-F disturbance_survival_violations=$($survivalViolations.Groups[1].Value)"
Write-Host "ECO.CAL1-F disturbance_seed_violations=$($seedViolations.Groups[1].Value)"
Write-Host "ECO.CAL1-F calibration_min_jaccard=$($minJaccard.Groups[1].Value)"
Write-Host "ECO.CAL1-F calibration_mean_jaccard=$($meanJaccard.Groups[1].Value)"
Write-Host "ECO.CAL1-F pairwise_contradictions=$($pairwise.Groups[1].Value)"
Write-Host "ECO.CAL1-F classification=$($classification.Groups[1].Value)"
Write-Host "ECO.CAL1-F candidate automated gates: PASS"
