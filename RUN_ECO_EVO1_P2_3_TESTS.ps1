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

Write-Host "=== ECO EVO1 P2.2 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_2_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.2 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.3 local population turnover + succession" "res://tests/research/ecology/eco_evo1_p2_3_local_population_succession_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.3 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_3_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.3 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_3_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$shadeDelta = [regex]::Match($acceptance, 'shade_delta=([-0-9.]+)')
$bankedGain = [regex]::Match($acceptance, 'banked_gain=([-0-9.]+)')
$reactivated = [regex]::Match($acceptance, 'reactivated=([0-9]+)')
$reproductionEvents = [regex]::Match($acceptance, 'reproduction_events=([0-9]+)')
$emitted = [regex]::Match($acceptance, 'emitted=([0-9]+)')
$shortMortality = [regex]::Match($acceptance, 'short_mortality=([-0-9.]+)')
$longMortality = [regex]::Match($acceptance, 'long_mortality=([-0-9.]+)')
$maxBiomass = [regex]::Match($acceptance, 'max_biomass=([-0-9.]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $shadeDelta, $bankedGain, $reactivated, $reproductionEvents, $emitted, $shortMortality, $longMortality, $maxBiomass)) {
    if (-not $m.Success) { throw "Unable to parse P2.3 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.3 fresh-process hash mismatch"
}

Write-Host "ECO.EVO1-P2.2 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.3 local population turnover + succession: PASS"
Write-Host "ECO.EVO1-P2.3 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.3 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 shade_delta=$($shadeDelta.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 banked_gain=$($bankedGain.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 reactivated=$($reactivated.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 reproduction_events=$($reproductionEvents.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 emitted=$($emitted.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 short_mortality=$($shortMortality.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 long_mortality=$($longMortality.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 max_biomass=$($maxBiomass.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.3 candidate automated gates: PASS"
