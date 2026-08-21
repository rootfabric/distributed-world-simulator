param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedP33KernelBlob = "43a25eb0e6677749162de99c251231c94d243dc1"
$ExpectedSnapshotHash = "ced399dbe56336d00953f9f369c462178b457b846a1c219de396d6724d77cc87"
$ExpectedTimelineHash = "7a686275024912134b758c19c42040507b97a696a06ad178111dd06c884c00e8"
$ExpectedSourceP33 = "84c802032740c23e65714c2e3c2c7e5679c3b51e95b8f61b4a6ca64408925779"
$ExpectedParentP32 = "172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$kernelBlob = (& git -C $RootDir hash-object -- "scripts/research/ecology/plant_spatial_dispersal_v1.gd").Trim()
if ($LASTEXITCODE -ne 0 -or $kernelBlob -ne $ExpectedP33KernelBlob) { throw "P3.3 kernel blob mismatch: expected=$ExpectedP33KernelBlob actual=$kernelBlob" }

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
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

Invoke-Godot "ECO OBS1.2 spatial boundary parser/preload" "res://tests/research/ecology/eco_obs1_spatial_read_only_acceptance.gd" -CheckOnly | Out-Null
Invoke-Godot "ECO OBS1.2 spatial scene parser/preload" "res://tests/research/ecology/eco_obs1_spatial_scene_smoke.gd" -CheckOnly | Out-Null
$runA = Invoke-Godot "ECO OBS1.2 spatial boundary A" "res://tests/research/ecology/eco_obs1_spatial_read_only_acceptance.gd"
$runB = Invoke-Godot "ECO OBS1.2 spatial boundary fresh process B" "res://tests/research/ecology/eco_obs1_spatial_read_only_acceptance.gd"
$scene = Invoke-Godot "ECO OBS1.2 spatial scene smoke" "res://tests/research/ecology/eco_obs1_spatial_scene_smoke.gd"

if ($runA -notmatch 'ECO\.OBS1\.2 Spatial Read-only Boundary: PASS') { throw "OBS1.2 boundary PASS marker missing" }
if ($runB -notmatch 'ECO\.OBS1\.2 Spatial Read-only Boundary: PASS') { throw "OBS1.2 fresh-process boundary PASS marker missing" }
if ($scene -notmatch 'ECO\.OBS1\.2 Spatial Scene Smoke: PASS') { throw "OBS1.2 scene PASS marker missing" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "$Name=([0-9a-f]{64})")
    if (-not $m.Success) { throw "Unable to parse $Name" }
    return $m.Groups[1].Value
}

$snapshotA = Parse-Hash $runA "snapshot_hash"
$snapshotB = Parse-Hash $runB "snapshot_hash"
$timelineA = Parse-Hash $runA "timeline_hash"
$timelineB = Parse-Hash $runB "timeline_hash"
$sourceA = Parse-Hash $runA "source_p3_3"
$sourceB = Parse-Hash $runB "source_p3_3"
$parentA = Parse-Hash $runA "parent_p3_2"
$parentB = Parse-Hash $runB "parent_p3_2"

if ($snapshotA -ne $snapshotB -or $snapshotA -ne $ExpectedSnapshotHash) { throw "OBS1.2 snapshot hash mismatch" }
if ($timelineA -ne $timelineB -or $timelineA -ne $ExpectedTimelineHash) { throw "OBS1.2 timeline hash mismatch" }
if ($sourceA -ne $sourceB -or $sourceA -ne $ExpectedSourceP33) { throw "OBS1.2 source P3.3 hash mismatch" }
if ($parentA -ne $parentB -or $parentA -ne $ExpectedParentP32) { throw "OBS1.2 parent P3.2 hash mismatch" }

Write-Host "ECO.OBS1.2 snapshot_hash=$snapshotA"
Write-Host "ECO.OBS1.2 timeline_hash=$timelineA"
Write-Host "ECO.OBS1.2 source_p3_3=$sourceA"
Write-Host "ECO.OBS1.2 spatial observer gates: PASS"
Write-Host "NOTE: OBS1.2 is NON_GATING and does not accept P3.3 or open P3.4."
