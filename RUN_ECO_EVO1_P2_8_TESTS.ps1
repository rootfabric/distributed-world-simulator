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

Invoke-GodotParsePreflight "ECO EVO1 P2.8 parser/preload preflight" "res://tests/research/ecology/eco_evo1_p2_8_save_restart_acceptance.gd"
$codecPreflight = Invoke-GodotScript "ECO EVO1 P2.8 checkpoint codec preflight" "res://tests/research/ecology/eco_evo1_p2_8_checkpoint_codec_preflight.gd"
$codecHash = [regex]::Match($codecPreflight, 'value_hash=([0-9a-f]{64})')
if (-not $codecHash.Success) { throw "Unable to parse P2.8 checkpoint codec preflight output" }

Write-Host "=== ECO EVO1 P2.7 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_7_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.7 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.8 deterministic save/restart plant world proof" "res://tests/research/ecology/eco_evo1_p2_8_save_restart_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.8 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_8_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.8 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_8_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$baseline = [regex]::Match($acceptance, 'baseline=([0-9a-f]{64})')
$resumed = [regex]::Match($acceptance, 'resumed=([0-9a-f]{64})')
$finalState = [regex]::Match($acceptance, 'final_state=([0-9a-f]{64})')
$checkpointA = [regex]::Match($acceptance, 'checkpoint_a=([0-9a-f]{64})')
$checkpointB = [regex]::Match($acceptance, 'checkpoint_b=([0-9a-f]{64})')
$diagnostics = [regex]::Match($acceptance, 'diagnostics=([0-9a-f]{64})')
$tamper = [regex]::Match($acceptance, 'tamper_rejected=(true|false)')
$cuts = [regex]::Match($acceptance, 'cuts=([0-9]+),([0-9]+) total=([0-9]+)')
$replayResumedA = [regex]::Match($replayA, 'resumed=([0-9a-f]{64})')
$replayResumedB = [regex]::Match($replayB, 'resumed=([0-9a-f]{64})')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $baseline, $resumed, $finalState, $checkpointA, $checkpointB, $diagnostics, $tamper, $cuts, $replayResumedA, $replayResumedB)) {
    if (-not $m.Success) { throw "Unable to parse P2.8 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.8 fresh-process aggregate hash mismatch"
}
if ($baseline.Groups[1].Value -ne $resumed.Groups[1].Value -or $baseline.Groups[1].Value -ne $replayResumedA.Groups[1].Value -or $baseline.Groups[1].Value -ne $replayResumedB.Groups[1].Value) {
    throw "P2.8 uninterrupted/save-restart result mismatch"
}
if ($tamper.Groups[1].Value -ne "true") { throw "P2.8 tamper rejection did not pass" }
if ($cuts.Groups[1].Value -ne "14" -or $cuts.Groups[2].Value -ne "18" -or $cuts.Groups[3].Value -ne "30") { throw "P2.8 checkpoint cut chronology mismatch" }

Write-Host "ECO.EVO1-P2.8 checkpoint codec preflight: PASS"
Write-Host "ECO.EVO1-P2.8 checkpoint codec value_hash=$($codecHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.8 deterministic save/restart plant world proof: PASS"
Write-Host "ECO.EVO1-P2.8 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.8 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 baseline_result_hash=$($baseline.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 final_state_hash=$($finalState.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 checkpoint_a_hash=$($checkpointA.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 checkpoint_b_hash=$($checkpointB.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 diagnostics_hash=$($diagnostics.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 tamper_rejected=$($tamper.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.8 cuts=$($cuts.Groups[1].Value),$($cuts.Groups[2].Value) total=$($cuts.Groups[3].Value)"
Write-Host "ECO.EVO1-P2.8 candidate automated gates: PASS"
