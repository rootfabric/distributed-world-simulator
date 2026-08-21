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

Invoke-GodotParsePreflight "ECO EVO1 P2.4 parser/preload preflight" "res://tests/research/ecology/eco_evo1_p2_4_patch_colonization_acceptance.gd"

Write-Host "=== ECO EVO1 P2.3 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_3_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.3 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.4 patch colonization + isolation + migration" "res://tests/research/ecology/eco_evo1_p2_4_patch_colonization_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.4 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_4_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.4 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_4_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$nearArrived = [regex]::Match($acceptance, 'near_arrived=([0-9]+)')
$farArrived = [regex]::Match($acceptance, 'far_arrived=([0-9]+)')
$nearRecruited = [regex]::Match($acceptance, 'near_recruited=([0-9]+)')
$farRecruited = [regex]::Match($acceptance, 'far_recruited=([0-9]+)')
$nearShort = [regex]::Match($acceptance, 'near_short=([0-9]+)')
$nearLong = [regex]::Match($acceptance, 'near_long=([0-9]+)')
$farShort = [regex]::Match($acceptance, 'far_short=([0-9]+)')
$farLong = [regex]::Match($acceptance, 'far_long=([0-9]+)')
$nearLongShare = [regex]::Match($acceptance, 'near_long_share=([-0-9.]+)')
$farLongShare = [regex]::Match($acceptance, 'far_long_share=([-0-9.]+)')
$westRouted = [regex]::Match($acceptance, 'west_routed=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $nearArrived, $farArrived, $nearRecruited, $farRecruited, $nearShort, $nearLong, $farShort, $farLong, $nearLongShare, $farLongShare, $westRouted)) {
    if (-not $m.Success) { throw "Unable to parse P2.4 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.4 fresh-process hash mismatch"
}

Write-Host "ECO.EVO1-P2.3 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.4 patch colonization / isolation / migration: PASS"
Write-Host "ECO.EVO1-P2.4 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.4 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 near_arrived=$($nearArrived.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 far_arrived=$($farArrived.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 near_recruited=$($nearRecruited.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 far_recruited=$($farRecruited.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 near_short=$($nearShort.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 near_long=$($nearLong.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 far_short=$($farShort.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 far_long=$($farLong.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 near_long_share=$($nearLongShare.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 far_long_share=$($farLongShare.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 west_routed=$($westRouted.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.4 candidate automated gates: PASS"
