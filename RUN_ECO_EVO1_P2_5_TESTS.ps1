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

function Invoke-GodotParsePreflight([string]$Label, [string]$ScriptPath) {
    Write-Host "=== $Label ==="
    $previous = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $output = & $GodotPath --headless --path $RootDir --check-only --script $ScriptPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previous) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
        else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
    }
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
}

Invoke-GodotParsePreflight "ECO EVO1 P2.5 parser/preload preflight" "res://tests/research/ecology/eco_evo1_p2_5_disturbance_recovery_acceptance.gd"

Write-Host "=== ECO EVO1 P2.4 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_4_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.4 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.5 disturbance + recovery" "res://tests/research/ecology/eco_evo1_p2_5_disturbance_recovery_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.5 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_5_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.5 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_5_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$mildLoss = [regex]::Match($acceptance, 'mild_loss=([-0-9.]+)')
$severeLoss = [regex]::Match($acceptance, 'severe_loss=([-0-9.]+)')
$shallowSurvival = [regex]::Match($acceptance, 'shallow_survival=([-0-9.]+)')
$deepSurvival = [regex]::Match($acceptance, 'deep_survival=([-0-9.]+)')
$mildBankKilled = [regex]::Match($acceptance, 'mild_bank_killed=([0-9]+)')
$severeBankKilled = [regex]::Match($acceptance, 'severe_bank_killed=([0-9]+)')
$recoveryGain = [regex]::Match($acceptance, 'recovery_gain=([-0-9.]+)')
$reactivated = [regex]::Match($acceptance, 'reactivated=([0-9]+)')
$repeatedFinal = [regex]::Match($acceptance, 'repeated_final=([-0-9.]+)')
$singleFinal = [regex]::Match($acceptance, 'single_severe_final=([-0-9.]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $mildLoss, $severeLoss, $shallowSurvival, $deepSurvival, $mildBankKilled, $severeBankKilled, $recoveryGain, $reactivated, $repeatedFinal, $singleFinal)) {
    if (-not $m.Success) { throw "Unable to parse P2.5 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.5 fresh-process hash mismatch"
}

Write-Host "ECO.EVO1-P2.4 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.5 disturbance / recovery: PASS"
Write-Host "ECO.EVO1-P2.5 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.5 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 mild_loss=$($mildLoss.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 severe_loss=$($severeLoss.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 shallow_survival=$($shallowSurvival.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 deep_survival=$($deepSurvival.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 mild_bank_killed=$($mildBankKilled.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 severe_bank_killed=$($severeBankKilled.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 recovery_gain=$($recoveryGain.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 reactivated=$($reactivated.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 repeated_final=$($repeatedFinal.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 single_severe_final=$($singleFinal.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.5 candidate automated gates: PASS"
