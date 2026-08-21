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

Write-Host "=== ECO EVO1 P2.1 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_1_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.1 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.2 establishment + recruitment + seed bank" "res://tests/research/ecology/eco_evo1_p2_2_establishment_seed_bank_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.2 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_2_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.2 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_2_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$favourable = [regex]::Match($acceptance, 'favourable=([0-9]+)')
$dry = [regex]::Match($acceptance, 'dry=([0-9]+)')
$flooded = [regex]::Match($acceptance, 'flooded=([0-9]+)')
$lowDormancyBank = [regex]::Match($acceptance, 'low_dormancy_bank=([0-9]+)')
$highDormancyBank = [regex]::Match($acceptance, 'high_dormancy_bank=([0-9]+)')
$shortBank = [regex]::Match($acceptance, 'short_bank=([0-9]+)')
$longBank = [regex]::Match($acceptance, 'long_bank=([0-9]+)')
$reactivation = [regex]::Match($acceptance, 'reactivation=([0-9]+)')
$boundary = [regex]::Match($acceptance, 'boundary_exported=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $favourable, $dry, $flooded, $lowDormancyBank, $highDormancyBank, $shortBank, $longBank, $reactivation, $boundary)) {
    if (-not $m.Success) { throw "Unable to parse P2.2 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.2 fresh-process hash mismatch"
}
if ([int]$boundary.Groups[1].Value -ne 80) { throw "P2.2 boundary export mismatch" }

Write-Host "ECO.EVO1-P2.1 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.2 establishment / recruitment / seed bank: PASS"
Write-Host "ECO.EVO1-P2.2 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.2 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 favourable=$($favourable.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 dry=$($dry.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 flooded=$($flooded.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 low_dormancy_bank=$($lowDormancyBank.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 high_dormancy_bank=$($highDormancyBank.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 short_bank=$($shortBank.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 long_bank=$($longBank.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 reactivation=$($reactivation.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 boundary_exported=$($boundary.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.2 candidate automated gates: PASS"
