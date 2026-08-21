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

Write-Host "=== ECO CAL1-D accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_D_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-D accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO CAL1-E combined mechanism matrix" "res://tests/research/ecology/eco_cal1_e_combined_mechanism_matrix_acceptance.gd"
$replayA = Invoke-GodotScript "ECO CAL1-E fresh process replay A" "res://tests/research/ecology/eco_cal1_e_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO CAL1-E fresh process replay B" "res://tests/research/ecology/eco_cal1_e_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$rows = [regex]::Match($acceptance, 'rows=([0-9]+)')
$contexts = [regex]::Match($acceptance, 'contexts=([0-9]+)')
$dense = [regex]::Match($acceptance, 'dense_nonzero=([0-9]+)')
$sparse = [regex]::Match($acceptance, 'sparse_nonzero=([0-9]+)')
$multiobjective = [regex]::Match($acceptance, 'multiobjective_contexts=([0-9]+)')
$multiPareto = [regex]::Match($acceptance, 'multi_pareto=([0-9]+)')
$paretoSignatures = [regex]::Match($acceptance, 'pareto_signatures=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $rows, $contexts, $dense, $sparse, $multiobjective, $multiPareto, $paretoSignatures)) {
    if (-not $m.Success) { throw "Unable to parse CAL1-E canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "CAL1-E fresh-process hash mismatch"
}
if ([int]$rows.Groups[1].Value -ne 192 -or [int]$contexts.Groups[1].Value -ne 24) {
    throw "CAL1-E matrix cardinality mismatch"
}
if ([int]$sparse.Groups[1].Value -ne 0) {
    throw "CAL1-E sparse no-overlap control is not neutral"
}

Write-Host "ECO.CAL1-D accepted regression: PASS"
Write-Host "ECO.CAL1-E combined mechanism matrix: PASS"
Write-Host "ECO.CAL1-E fresh-process replay: PASS"
Write-Host "ECO.CAL1-E aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.CAL1-E rows=$($rows.Groups[1].Value)"
Write-Host "ECO.CAL1-E contexts=$($contexts.Groups[1].Value)"
Write-Host "ECO.CAL1-E dense_nonzero=$($dense.Groups[1].Value)"
Write-Host "ECO.CAL1-E sparse_nonzero=$($sparse.Groups[1].Value)"
Write-Host "ECO.CAL1-E multiobjective_contexts=$($multiobjective.Groups[1].Value)"
Write-Host "ECO.CAL1-E multi_pareto=$($multiPareto.Groups[1].Value)"
Write-Host "ECO.CAL1-E pareto_signatures=$($paretoSignatures.Groups[1].Value)"
Write-Host "ECO.CAL1-E candidate automated gates: PASS"
