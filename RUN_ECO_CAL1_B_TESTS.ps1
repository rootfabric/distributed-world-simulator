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

Write-Host "=== ECO CAL1-A accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_A_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-A accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO CAL1-B relative vertical light competition" "res://tests/research/ecology/eco_cal1_b_relative_vertical_light_competition_acceptance.gd"
$replayA = Invoke-GodotScript "ECO CAL1-B fresh process replay A" "res://tests/research/ecology/eco_cal1_b_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO CAL1-B fresh process replay B" "res://tests/research/ecology/eco_cal1_b_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$denseDelta = [regex]::Match($acceptance, 'dense_delta=([-0-9.]+)')
$sparseDelta = [regex]::Match($acceptance, 'sparse_delta=([-0-9.]+)')
$ratio = [regex]::Match($acceptance, 'dense_to_sparse=([-0-9.]+)')
$referenceBefore = [regex]::Match($acceptance, 'reference_gap_before=([-0-9.]+)')
$referenceAfter = [regex]::Match($acceptance, 'reference_gap_after=([-0-9.]+)')
$dryBefore = [regex]::Match($acceptance, 'dry_gap_before=([-0-9.]+)')
$dryAfter = [regex]::Match($acceptance, 'dry_gap_after=([-0-9.]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $denseDelta, $sparseDelta, $ratio, $referenceBefore, $referenceAfter, $dryBefore, $dryAfter)) {
    if (-not $m.Success) { throw "Unable to parse CAL1-B canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "CAL1-B fresh-process hash mismatch"
}

Write-Host "ECO.CAL1-A accepted regression: PASS"
Write-Host "ECO.CAL1-B relative vertical light competition: PASS"
Write-Host "ECO.CAL1-B fresh-process replay: PASS"
Write-Host "ECO.CAL1-B aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.CAL1-B dense_delta=$($denseDelta.Groups[1].Value)"
Write-Host "ECO.CAL1-B sparse_delta=$($sparseDelta.Groups[1].Value)"
Write-Host "ECO.CAL1-B dense_to_sparse=$($ratio.Groups[1].Value)"
Write-Host "ECO.CAL1-B reference_gap_before=$($referenceBefore.Groups[1].Value)"
Write-Host "ECO.CAL1-B reference_gap_after=$($referenceAfter.Groups[1].Value)"
Write-Host "ECO.CAL1-B dry_gap_before=$($dryBefore.Groups[1].Value)"
Write-Host "ECO.CAL1-B dry_gap_after=$($dryAfter.Groups[1].Value)"
Write-Host "ECO.CAL1-B candidate automated gates: PASS"
