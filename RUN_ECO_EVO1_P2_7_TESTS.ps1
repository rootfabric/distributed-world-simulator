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

Invoke-GodotParsePreflight "ECO EVO1 P2.7 parser/preload preflight" "res://tests/research/ecology/eco_evo1_p2_7_lineage_divergence_acceptance.gd"

Write-Host "=== ECO EVO1 P2.6 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_6_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.6 accepted parent regression failed" }

$acceptance = Invoke-GodotScript "ECO EVO1 P2.7 lineage divergence diagnostics" "res://tests/research/ecology/eco_evo1_p2_7_lineage_divergence_acceptance.gd"
$replayA = Invoke-GodotScript "ECO EVO1 P2.7 fresh process replay A" "res://tests/research/ecology/eco_evo1_p2_7_restart_replay_probe.gd"
$replayB = Invoke-GodotScript "ECO EVO1 P2.7 fresh process replay B" "res://tests/research/ecology/eco_evo1_p2_7_restart_replay_probe.gd"

$acceptanceHash = [regex]::Match($acceptance, 'aggregate_hash=([0-9a-f]{64})')
$replayHashA = [regex]::Match($replayA, 'aggregate_hash=([0-9a-f]{64})')
$replayHashB = [regex]::Match($replayB, 'aggregate_hash=([0-9a-f]{64})')
$candidate = [regex]::Match($acceptance, 'candidate=(true|false)')
$connected = [regex]::Match($acceptance, 'connected=(true|false)')
$similar = [regex]::Match($acceptance, 'similar=(true|false)')
$recent = [regex]::Match($acceptance, 'recent=(true|false)')
$splitAge = [regex]::Match($acceptance, 'split_age=([0-9]+)')
$isolation = [regex]::Match($acceptance, 'isolation=([0-9.]+)')
$connection = [regex]::Match($acceptance, 'connection=([0-9.]+)')
$genome = [regex]::Match($acceptance, 'genome=([0-9.]+)')
$ecology = [regex]::Match($acceptance, 'ecology=([0-9.]+)')
$connectedConnection = [regex]::Match($acceptance, 'connected_connection=([0-9.]+)')
$similarGenome = [regex]::Match($acceptance, 'similar_genome=([0-9.]+)')
$recentSplit = [regex]::Match($acceptance, 'recent_split_age=([0-9]+)')

foreach ($m in @($acceptanceHash, $replayHashA, $replayHashB, $candidate, $connected, $similar, $recent, $splitAge, $isolation, $connection, $genome, $ecology, $connectedConnection, $similarGenome, $recentSplit)) {
    if (-not $m.Success) { throw "Unable to parse P2.7 canonical output" }
}
if ($acceptanceHash.Groups[1].Value -ne $replayHashA.Groups[1].Value -or $acceptanceHash.Groups[1].Value -ne $replayHashB.Groups[1].Value) {
    throw "P2.7 fresh-process hash mismatch"
}
if ($candidate.Groups[1].Value -ne "true" -or $connected.Groups[1].Value -ne "false" -or $similar.Groups[1].Value -ne "false" -or $recent.Groups[1].Value -ne "false") {
    throw "P2.7 controlled classification mismatch"
}

Write-Host "ECO.EVO1-P2.6 accepted regression: PASS"
Write-Host "ECO.EVO1-P2.7 lineage divergence / speciation candidate diagnostics: PASS"
Write-Host "ECO.EVO1-P2.7 fresh-process replay: PASS"
Write-Host "ECO.EVO1-P2.7 aggregate_hash=$($acceptanceHash.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 candidate=$($candidate.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 connected=$($connected.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 similar=$($similar.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 recent=$($recent.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 split_age=$($splitAge.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 isolation=$($isolation.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 connection=$($connection.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 genome=$($genome.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 ecology=$($ecology.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 connected_connection=$($connectedConnection.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 similar_genome=$($similarGenome.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 recent_split_age=$($recentSplit.Groups[1].Value)"
Write-Host "ECO.EVO1-P2.7 candidate automated gates: PASS"
