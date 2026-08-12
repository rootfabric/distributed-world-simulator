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

Invoke-GodotParsePreflight "ECO EVO1 P2.6 parser/preload preflight" "res://tests/research/ecology/eco_evo1_p2_6_long_horizon_biogeography_acceptance.gd"

Write-Host "=== ECO EVO1 P2.5 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_5_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.5 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.6 long-horizon biogeography" "res://tests/research/ecology/eco_evo1_p2_6_long_horizon_biogeography_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.6 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_6_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.6 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_6_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$colonized = [regex]::Match($acceptance, 'colonized=([-0-9]+)')
$extinct = [regex]::Match($acceptance, 'extinct=([-0-9]+)')
$recolonized = [regex]::Match($acceptance, 'recolonized=([-0-9]+)')
$longPatchYears = [regex]::Match($acceptance, 'long_patch_years=([0-9]+)')
$shortPatchYears = [regex]::Match($acceptance, 'short_patch_years=([0-9]+)')
$farLong = [regex]::Match($acceptance, 'far_long=([0-9]+)')
$farShort = [regex]::Match($acceptance, 'far_short=([0-9]+)')
$eventAbsence = [regex]::Match($acceptance, 'event_absence=([0-9]+)')
$controlAbsence = [regex]::Match($acceptance, 'control_absence=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $colonized, $extinct, $recolonized, $longPatchYears, $shortPatchYears, $farLong, $farShort, $eventAbsence, $controlAbsence)) {
    if (-not $m.Success) { throw "Unable to parse P2.6 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.6 fresh-process hash mismatch"
}

Write-Host "ECO.EVO1-P2.5 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.6 long-horizon biogeography: PASS"
Write-Host "ECO.EVO1-P2.6 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.6 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 colonized=$($colonized.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 extinct=$($extinct.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 recolonized=$($recolonized.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 long_patch_years=$($longPatchYears.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 short_patch_years=$($shortPatchYears.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 far_long=$($farLong.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 far_short=$($farShort.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 event_absence=$($eventAbsence.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 control_absence=$($controlAbsence.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.6 candidate automated gates: PASS"
