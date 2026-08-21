param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP37 = "ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a"
$ExpectedAggregate = "6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0"
$ExpectedCheckpointSha = "1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367"
$ExpectedFinalState = "1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$ParentValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-7-multi-niche-coexistence-validation.json"
if (-not (Test-Path -LiteralPath $ParentValidationPath -PathType Leaf)) { throw "P3.7 validation file not found: $ParentValidationPath" }
$parentValidation = Get-Content -LiteralPath $ParentValidationPath -Raw | ConvertFrom-Json
$parentStatus = [string]$parentValidation.status
if (-not $parentStatus.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.7 parent is not ACCEPTED: status=$parentStatus"
}

function Invoke-Godot([string]$Label, [string]$ScriptPath) {
    Write-Host "=== $Label ==="
    $previousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $output = & $GodotPath --headless --path $RootDir --script $ScriptPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousBreakpoint) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
        else { $env:BREAKPOINT_RUNTIME_DISABLED = $previousBreakpoint }
    }
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

Write-Host "=== ECO P3.8 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P3.8 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P3.8 parser/preload preflight emitted Godot ERROR output" }

Write-Host "=== ECO P3.7 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P3_7_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P3.7 accepted parent regression failed" }

$runA = Invoke-Godot "ECO P3.8 ecosystem persistence A" "res://tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd"
$runB = Invoke-Godot "ECO P3.8 ecosystem persistence fresh process B" "res://tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd"
if ($runA -ne $runB) { throw "P3.8 fresh-process logs are not byte-identical" }

$aggregateA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$aggregateB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p3_7=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p3_7=([0-9a-f]{64})')
$checkpointA = [regex]::Match($runA, 'checkpoint_sha256=([0-9a-f]{64})')
$finalA = [regex]::Match($runA, 'final_state_hash=([0-9a-f]{64})')
foreach ($match in @($aggregateA,$aggregateB,$parentA,$parentB,$checkpointA,$finalA)) {
    if (-not $match.Success) { throw "Unable to parse P3.8 canonical output" }
}
if ($aggregateA.Groups[1].Value -ne $aggregateB.Groups[1].Value) { throw "P3.8 fresh-process aggregate mismatch" }
if ($aggregateA.Groups[1].Value -ne $ExpectedAggregate) { throw "P3.8 aggregate identity mismatch: expected=$ExpectedAggregate actual=$($aggregateA.Groups[1].Value)" }
if ($parentA.Groups[1].Value -ne $ExpectedParentP37 -or $parentB.Groups[1].Value -ne $ExpectedParentP37) { throw "P3.8 P3.7 parent identity mismatch" }
if ($checkpointA.Groups[1].Value -ne $ExpectedCheckpointSha) { throw "P3.8 checkpoint byte identity mismatch" }
if ($finalA.Groups[1].Value -ne $ExpectedFinalState) { throw "P3.8 final state identity mismatch" }

$resultsDir = Join-Path $RootDir "test-results/ecology"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$checkpointPath = Join-Path $resultsDir "p3-8-cross-process-$PID.bin"
$oldMode = $env:ECO_P3_8_MODE
$oldPath = $env:ECO_P3_8_CHECKPOINT_PATH
try {
    $env:ECO_P3_8_CHECKPOINT_PATH = $checkpointPath
    $env:ECO_P3_8_MODE = "write_cut"
    $writer = Invoke-Godot "ECO P3.8 cross-process checkpoint writer" "res://tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd"
    if (-not (Test-Path -LiteralPath $checkpointPath -PathType Leaf)) { throw "P3.8 writer did not create checkpoint file" }
    $env:ECO_P3_8_MODE = "resume_cut"
    $resume = Invoke-Godot "ECO P3.8 cross-process checkpoint resume" "res://tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd"

    $writerCheckpoint = [regex]::Match($writer, 'checkpoint_sha256=([0-9a-f]{64})')
    $writerExpected = [regex]::Match($writer, 'expected_final_state_hash=([0-9a-f]{64})')
    $resumeFinal = [regex]::Match($resume, 'final_state_hash=([0-9a-f]{64})')
    foreach ($match in @($writerCheckpoint,$writerExpected,$resumeFinal)) {
        if (-not $match.Success) { throw "Unable to parse P3.8 cross-process output" }
    }
    if ($writerCheckpoint.Groups[1].Value -ne $ExpectedCheckpointSha) { throw "P3.8 cross-process checkpoint SHA mismatch" }
    if ($writerExpected.Groups[1].Value -ne $ExpectedFinalState -or $resumeFinal.Groups[1].Value -ne $ExpectedFinalState) { throw "P3.8 cross-process resume final state mismatch" }
}
finally {
    if ($null -eq $oldMode) { Remove-Item Env:ECO_P3_8_MODE -ErrorAction SilentlyContinue } else { $env:ECO_P3_8_MODE = $oldMode }
    if ($null -eq $oldPath) { Remove-Item Env:ECO_P3_8_CHECKPOINT_PATH -ErrorAction SilentlyContinue } else { $env:ECO_P3_8_CHECKPOINT_PATH = $oldPath }
    Remove-Item -LiteralPath $checkpointPath -Force -ErrorAction SilentlyContinue
}

Write-Host "ECO.P3.7 accepted parent regression: PASS"
Write-Host "ECO.P3.8 deterministic persistence fresh-process determinism: PASS"
Write-Host "ECO.P3.8 cross-process save/restart: PASS"
Write-Host "ECO.P3.8 aggregate_hash=$($aggregateA.Groups[1].Value)"
Write-Host "ECO.P3.8 parent_p3_7=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.8 checkpoint_sha256=$($checkpointA.Groups[1].Value)"
Write-Host "ECO.P3.8 final_state_hash=$($finalA.Groups[1].Value)"
Write-Host "ECO.P3.8 candidate automated gates: PASS"
