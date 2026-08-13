param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedSnapshotHash = "1a71d293354516adfb0c07752623d5b1cb80b5d1f7674feb06dfa76e2efb8e57"
$ExpectedTimelineHash = "0d5d35e7b04fa6921dc3d0f8f1827055f68aeb5e91e46c17db3e5b4572f21031"
$ExpectedBoundarySource = "9667aba9cd8d33668abcaf7b1123e1ceb846dc59f48a646de91c7cc7bec35dac"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

function Invoke-Godot([string]$Label, [string]$ScriptPath, [switch]$CheckOnly) {
    Write-Host "=== $Label ==="
    $previous = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        if ($CheckOnly) { $output = & $GodotPath --headless --path $RootDir --check-only --script $ScriptPath 2>&1 }
        else { $output = & $GodotPath --headless --path $RootDir --script $ScriptPath 2>&1 }
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

Invoke-Godot "ECO OBS1 snapshot parser/preload" "res://tests/research/ecology/eco_obs1_read_only_acceptance.gd" -CheckOnly | Out-Null
Invoke-Godot "ECO OBS1 scene parser/preload" "res://tests/research/ecology/eco_obs1_scene_smoke.gd" -CheckOnly | Out-Null
$boundary = Invoke-Godot "ECO OBS1 read-only boundary" "res://tests/research/ecology/eco_obs1_read_only_acceptance.gd"
$scene = Invoke-Godot "ECO OBS1 scene smoke" "res://tests/research/ecology/eco_obs1_scene_smoke.gd"
if ($boundary -notmatch 'ECO\.OBS1 Read-only Snapshot Boundary: PASS') { throw "OBS1 boundary PASS marker missing" }
if ($scene -notmatch 'ECO\.OBS1 Scene Smoke: PASS') { throw "OBS1 scene PASS marker missing" }
$snapshot = [regex]::Match($boundary, 'snapshot_hash=([0-9a-f]{64})')
$timeline = [regex]::Match($boundary, 'timeline_hash=([0-9a-f]{64})')
$source = [regex]::Match($boundary, 'source_p3_2=([0-9a-f]{64})')
foreach ($m in @($snapshot, $timeline, $source)) {
    if (-not $m.Success) { throw "Unable to parse OBS1 deterministic evidence" }
}
if ($snapshot.Groups[1].Value -ne $ExpectedSnapshotHash) { throw "OBS1 snapshot hash mismatch" }
if ($timeline.Groups[1].Value -ne $ExpectedTimelineHash) { throw "OBS1 timeline hash mismatch" }
if ($source.Groups[1].Value -ne $ExpectedBoundarySource) { throw "OBS1 boundary source hash mismatch" }
Write-Host "ECO.OBS1 snapshot_hash=$($snapshot.Groups[1].Value)"
Write-Host "ECO.OBS1 timeline_hash=$($timeline.Groups[1].Value)"
Write-Host "ECO.OBS1 targeted observer gates: PASS"
Write-Host "NOTE: OBS1 is NON_GATING and does not change P3.1/P3.2 acceptance status."
