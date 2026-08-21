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

$ph3 = Invoke-GodotScript "ECO PH3 accepted morphology/resource regression" "res://tests/research/ecology/eco_ph3_morphology_resource_coupling_acceptance.gd"
$ph3Restart = Invoke-GodotScript "ECO PH3 accepted fresh-process regression" "res://tests/research/ecology/eco_ph3_restart_replay_probe.gd"
$ph3c = Invoke-GodotScript "ECO PH3C accepted morphology-aware selection regression" "res://tests/research/ecology/eco_ph3c_morphology_aware_selection_acceptance.gd"
$ph3cRestart = Invoke-GodotScript "ECO PH3C accepted replay regression" "res://tests/research/ecology/eco_ph3c_restart_replay_probe.gd"
$cal1 = Invoke-GodotScript "ECO CAL1-A baseline decomposition" "res://tests/research/ecology/eco_cal1_a_baseline_decomposition_acceptance.gd"
$restartA = Invoke-GodotScript "ECO CAL1-A fresh process replay A" "res://tests/research/ecology/eco_cal1_a_restart_replay_probe.gd"
$restartB = Invoke-GodotScript "ECO CAL1-A fresh process replay B" "res://tests/research/ecology/eco_cal1_a_restart_replay_probe.gd"

$baselineMatch = [regex]::Match($cal1, 'baseline_hash=([0-9a-f]{64})')
$pairwiseMatch = [regex]::Match($cal1, 'legacy_ph3c_pairwise_hash=([0-9a-f]{64})')
$classificationMatch = [regex]::Match($cal1, 'classification=([A-Z0-9_]+)')
$restartAMatch = [regex]::Match($restartA, 'baseline_hash=([0-9a-f]{64})')
$restartBMatch = [regex]::Match($restartB, 'baseline_hash=([0-9a-f]{64})')
$restartAPairwise = [regex]::Match($restartA, 'legacy_ph3c_pairwise_hash=([0-9a-f]{64})')
$restartBPairwise = [regex]::Match($restartB, 'legacy_ph3c_pairwise_hash=([0-9a-f]{64})')
if (-not $baselineMatch.Success) { throw "Unable to parse CAL1-A baseline hash" }
if (-not $pairwiseMatch.Success) { throw "Unable to parse CAL1-A legacy PH3C pairwise hash" }
if (-not $classificationMatch.Success) { throw "Unable to parse CAL1-A dominance classification" }
if (-not $restartAMatch.Success -or -not $restartBMatch.Success) { throw "Unable to parse CAL1-A fresh-process hashes" }
if (-not $restartAPairwise.Success -or -not $restartBPairwise.Success) { throw "Unable to parse CAL1-A fresh-process PH3C hashes" }
if ($baselineMatch.Groups[1].Value -ne $restartAMatch.Groups[1].Value -or $restartAMatch.Groups[1].Value -ne $restartBMatch.Groups[1].Value) {
    throw "CAL1-A fresh-process baseline replay mismatch"
}
if ($pairwiseMatch.Groups[1].Value -ne $restartAPairwise.Groups[1].Value -or $restartAPairwise.Groups[1].Value -ne $restartBPairwise.Groups[1].Value) {
    throw "CAL1-A fresh-process legacy PH3C replay mismatch"
}

Write-Host "ECO.PH3 accepted regression: PASS"
Write-Host "ECO.PH3C accepted regression: PASS"
Write-Host "ECO.CAL1-A baseline decomposition: PASS"
Write-Host "ECO.CAL1-A fresh-process replay: PASS"
Write-Host "ECO.CAL1-A baseline_hash=$($baselineMatch.Groups[1].Value)"
Write-Host "ECO.CAL1-A legacy_ph3c_pairwise_hash=$($pairwiseMatch.Groups[1].Value)"
Write-Host "ECO.CAL1-A dominance_classification=$($classificationMatch.Groups[1].Value)"
Write-Host "ECO.CAL1-A candidate automated gates: PASS"
