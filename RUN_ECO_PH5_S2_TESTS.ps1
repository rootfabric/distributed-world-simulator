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

$ph5 = Invoke-GodotScript "ECO PH5-S1 accepted render-description regression" "res://tests/research/ecology/eco_ph5_render_materialization_acceptance.gd"
$ph5Restart = Invoke-GodotScript "ECO PH5-S1 accepted fresh-process replay" "res://tests/research/ecology/eco_ph5_restart_replay_probe.gd"
$focused = Invoke-GodotScript "ECO PH5-S2 real 3D materialization" "res://tests/research/ecology/eco_ph5_s2_3d_materialization_acceptance.gd"
$smoke = Invoke-GodotScript "ECO PH5-S2 3D visual lab smoke" "res://tests/research/ecology/eco_ph5_s2_visual_lab_smoke.gd"
$restart = Invoke-GodotScript "ECO PH5-S2 fresh-process replay" "res://tests/research/ecology/eco_ph5_s2_restart_replay_probe.gd"

$focusedMatch = [regex]::Match($focused, 'reference_branch_leaf_geometry_hash=([0-9a-f]{64}) full_geometry_hash=([0-9a-f]{64})')
$restartMatch = [regex]::Match($restart, 'branch_leaf=([0-9a-f]{64}) full=([0-9a-f]{64})')
if (-not $focusedMatch.Success) { throw "Unable to parse PH5-S2 focused hashes" }
if (-not $restartMatch.Success) { throw "Unable to parse PH5-S2 restart hashes" }
for ($i = 1; $i -le 2; $i++) {
    if ($focusedMatch.Groups[$i].Value -ne $restartMatch.Groups[$i].Value) {
        throw "ECO.PH5-S2 REPLAY_DIVERGENCE: focused/restart hash group $i mismatch"
    }
}

Write-Host "ECO.PH5-S1 parent focused/restart: PASS"
Write-Host "ECO.PH5-S2 focused 3D materialization: PASS"
Write-Host "ECO.PH5-S2 visual lab smoke: PASS"
Write-Host "ECO.PH5-S2 restart replay: PASS"
Write-Host "ECO.PH5-S2 reference_branch_leaf_geometry_hash=$($focusedMatch.Groups[1].Value)"
Write-Host "ECO.PH5-S2 full_geometry_hash=$($focusedMatch.Groups[2].Value)"
Write-Host "ECO.PH5-S2 3D tapered branch tubes + instanced foliage candidate: PASS"
