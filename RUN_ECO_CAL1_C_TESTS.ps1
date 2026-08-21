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

Write-Host "=== ECO CAL1-B accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_B_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-B accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO CAL1-C crown + root spatial competition" "res://tests/research/ecology/eco_cal1_c_crown_root_spatial_competition_acceptance.gd"
$replayA = Invoke-GodotScript "ECO CAL1-C fresh process replay A" "res://tests/research/ecology/eco_cal1_c_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO CAL1-C fresh process replay B" "res://tests/research/ecology/eco_cal1_c_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$crownCloseOverlap = [regex]::Match($acceptance, 'crown_close_overlap=([-0-9.]+)')
$crownFarOverlap = [regex]::Match($acceptance, 'crown_far_overlap=([-0-9.]+)')
$crownCloseLoss = [regex]::Match($acceptance, 'crown_close_loss=([-0-9.]+)')
$crownFarLoss = [regex]::Match($acceptance, 'crown_far_loss=([-0-9.]+)')
$highNeighbourLoss = [regex]::Match($acceptance, 'high_neighbour_loss=([-0-9.]+)')
$lowNeighbourLoss = [regex]::Match($acceptance, 'low_neighbour_loss=([-0-9.]+)')
$rootDenseDeep = [regex]::Match($acceptance, 'root_dense_delta_deep=([-0-9.]+)')
$rootDenseShallow = [regex]::Match($acceptance, 'root_dense_delta_shallow=([-0-9.]+)')
$rootSparseDeep = [regex]::Match($acceptance, 'root_sparse_delta_deep=([-0-9.]+)')
$rootSparseShallow = [regex]::Match($acceptance, 'root_sparse_delta_shallow=([-0-9.]+)')
$deepClaim = [regex]::Match($acceptance, 'deep_claim=([-0-9.]+)')
$shallowClaim = [regex]::Match($acceptance, 'shallow_claim=([-0-9.]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $crownCloseOverlap, $crownFarOverlap, $crownCloseLoss, $crownFarLoss, $highNeighbourLoss, $lowNeighbourLoss, $rootDenseDeep, $rootDenseShallow, $rootSparseDeep, $rootSparseShallow, $deepClaim, $shallowClaim)) {
    if (-not $m.Success) { throw "Unable to parse CAL1-C canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "CAL1-C fresh-process hash mismatch"
}

Write-Host "ECO.CAL1-B accepted regression: PASS"
Write-Host "ECO.CAL1-C crown + root spatial competition: PASS"
Write-Host "ECO.CAL1-C fresh-process replay: PASS"
Write-Host "ECO.CAL1-C aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.CAL1-C crown_close_overlap=$($crownCloseOverlap.Groups[1].Value)"
Write-Host "ECO.CAL1-C crown_far_overlap=$($crownFarOverlap.Groups[1].Value)"
Write-Host "ECO.CAL1-C crown_close_loss=$($crownCloseLoss.Groups[1].Value)"
Write-Host "ECO.CAL1-C crown_far_loss=$($crownFarLoss.Groups[1].Value)"
Write-Host "ECO.CAL1-C high_neighbour_loss=$($highNeighbourLoss.Groups[1].Value)"
Write-Host "ECO.CAL1-C low_neighbour_loss=$($lowNeighbourLoss.Groups[1].Value)"
Write-Host "ECO.CAL1-C root_dense_delta_deep=$($rootDenseDeep.Groups[1].Value)"
Write-Host "ECO.CAL1-C root_dense_delta_shallow=$($rootDenseShallow.Groups[1].Value)"
Write-Host "ECO.CAL1-C root_sparse_delta_deep=$($rootSparseDeep.Groups[1].Value)"
Write-Host "ECO.CAL1-C root_sparse_delta_shallow=$($rootSparseShallow.Groups[1].Value)"
Write-Host "ECO.CAL1-C deep_claim=$($deepClaim.Groups[1].Value)"
Write-Host "ECO.CAL1-C shallow_claim=$($shallowClaim.Groups[1].Value)"
Write-Host "ECO.CAL1-C candidate automated gates: PASS"
