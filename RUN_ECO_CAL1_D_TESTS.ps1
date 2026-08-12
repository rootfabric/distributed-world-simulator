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

Write-Host "=== ECO CAL1-C accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_C_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-C accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO CAL1-D lifecycle payoff acceptance" "res://tests/research/ecology/eco_cal1_d_lifecycle_payoff_acceptance.gd"
$replayA = Invoke-GodotScript "ECO CAL1-D fresh process replay A" "res://tests/research/ecology/eco_cal1_d_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO CAL1-D fresh process replay B" "res://tests/research/ecology/eco_cal1_d_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$maturityRatio = [regex]::Match($acceptance, 'maturity_seed_ratio=([-0-9.]+)')
$reserveRatio = [regex]::Match($acceptance, 'reserve_seed_ratio=([-0-9.]+)')
$releaseRatio = [regex]::Match($acceptance, 'release_distance_ratio=([-0-9.]+)')
$fastMaturity = [regex]::Match($acceptance, 'fast_maturity=([-0-9.]+)')
$slowMaturity = [regex]::Match($acceptance, 'slow_maturity=([-0-9.]+)')
$shortAmortized = [regex]::Match($acceptance, 'short_amortized=([-0-9.]+)')
$longAmortized = [regex]::Match($acceptance, 'long_amortized=([-0-9.]+)')
$shallowSurvival = [regex]::Match($acceptance, 'shallow_survival=([-0-9.]+)')
$deepSurvival = [regex]::Match($acceptance, 'deep_survival=([-0-9.]+)')
$fastRecovery = [regex]::Match($acceptance, 'fast_recovery=([-0-9.]+)')
$slowRecovery = [regex]::Match($acceptance, 'slow_recovery=([-0-9.]+)')
$mildSeeds = [regex]::Match($acceptance, 'mild_post_seeds=([-0-9.]+)')
$severeSeeds = [regex]::Match($acceptance, 'severe_post_seeds=([-0-9.]+)')

foreach ($m in @($acceptanceHash,$replayHashA,$replayHashB,$maturityRatio,$reserveRatio,$releaseRatio,$fastMaturity,$slowMaturity,$shortAmortized,$longAmortized,$shallowSurvival,$deepSurvival,$fastRecovery,$slowRecovery,$mildSeeds,$severeSeeds)) {
    if (-not $m.Success) { throw "Unable to parse CAL1-D canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "CAL1-D fresh-process hash mismatch"
}

Write-Host "ECO.CAL1-C accepted regression: PASS"
Write-Host "ECO.CAL1-D lifecycle payoffs: PASS"
Write-Host "ECO.CAL1-D fresh-process replay: PASS"
Write-Host "ECO.CAL1-D aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.CAL1-D maturity_seed_ratio=$($maturityRatio.Groups[1].Value)"
Write-Host "ECO.CAL1-D reserve_seed_ratio=$($reserveRatio.Groups[1].Value)"
Write-Host "ECO.CAL1-D release_distance_ratio=$($releaseRatio.Groups[1].Value)"
Write-Host "ECO.CAL1-D fast_maturity=$($fastMaturity.Groups[1].Value)"
Write-Host "ECO.CAL1-D slow_maturity=$($slowMaturity.Groups[1].Value)"
Write-Host "ECO.CAL1-D short_amortized=$($shortAmortized.Groups[1].Value)"
Write-Host "ECO.CAL1-D long_amortized=$($longAmortized.Groups[1].Value)"
Write-Host "ECO.CAL1-D shallow_survival=$($shallowSurvival.Groups[1].Value)"
Write-Host "ECO.CAL1-D deep_survival=$($deepSurvival.Groups[1].Value)"
Write-Host "ECO.CAL1-D fast_recovery=$($fastRecovery.Groups[1].Value)"
Write-Host "ECO.CAL1-D slow_recovery=$($slowRecovery.Groups[1].Value)"
Write-Host "ECO.CAL1-D mild_post_seeds=$($mildSeeds.Groups[1].Value)"
Write-Host "ECO.CAL1-D severe_post_seeds=$($severeSeeds.Groups[1].Value)"
Write-Host "ECO.CAL1-D candidate automated gates: PASS"
