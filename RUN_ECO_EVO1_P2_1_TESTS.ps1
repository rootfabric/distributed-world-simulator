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

Write-Host "=== ECO CAL1-F accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_CAL1_F_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "CAL1-F accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.1 seed dispersal kernel" "res://tests/research/ecology/eco_evo1_p2_1_seed_dispersal_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.1 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_1_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.1 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_1_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$distanceRatio = [regex]::Match($acceptance, 'distance_ratio=([0-9.\-]+)')
$releaseRatio = [regex]::Match($acceptance, 'release_ratio=([0-9.\-]+)')
$boundaryOutside = [regex]::Match($acceptance, 'boundary_outside=([0-9]+)')
$localCount = [regex]::Match($acceptance, 'local=([0-9]+)')
$tailCount = [regex]::Match($acceptance, 'long_tail=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $distanceRatio, $releaseRatio, $boundaryOutside, $localCount, $tailCount)) {
    if (-not $m.Success) { throw "Unable to parse EVO1 P2.1 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "EVO1 P2.1 fresh-process hash mismatch"
}
if ([double]$distanceRatio.Groups[1].Value -lt 5.999999 -or [double]$distanceRatio.Groups[1].Value -gt 6.000001) {
    throw "EVO1 P2.1 inherited dispersal scaling mismatch"
}
if ([double]$releaseRatio.Groups[1].Value -lt 1.999999 -or [double]$releaseRatio.Groups[1].Value -gt 2.000001) {
    throw "EVO1 P2.1 release-height scaling mismatch"
}
if ([int]$boundaryOutside.Groups[1].Value -le 0) {
    throw "EVO1 P2.1 boundary accounting did not exercise exported seeds"
}

Write-Host "ECO.CAL1-F accepted regression: PASS"
Write-Host "ECO.EVO1-P2.1 seed dispersal kernel: PASS"
Write-Host "ECO.EVO1-P2.1 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.1 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 distance_ratio=$($distanceRatio.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 release_ratio=$($releaseRatio.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 boundary_outside=$($boundaryOutside.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 local=$($localCount.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 long_tail=$($tailCount.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.1 candidate automated gates: PASS"
