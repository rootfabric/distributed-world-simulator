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
    $output = & $GodotPath --headless --path $RootDir --script $ScriptPath 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    return ($output -join "`n")
}

$ph4 = Invoke-GodotScript "ECO PH4 accepted lifecycle regression" "res://tests/research/ecology/eco_ph4_seed_lifecycle_acceptance.gd"
$ph4Restart = Invoke-GodotScript "ECO PH4 accepted restart replay" "res://tests/research/ecology/eco_ph4_restart_replay_probe.gd"
$focused = Invoke-GodotScript "ECO PH5 render materialization acceptance" "res://tests/research/ecology/eco_ph5_render_materialization_acceptance.gd"
$smoke = Invoke-GodotScript "ECO PH5 visual lab headless smoke" "res://tests/research/ecology/eco_ph5_visual_lab_smoke.gd"
$restart = Invoke-GodotScript "ECO PH5 fresh-process restart replay" "res://tests/research/ecology/eco_ph5_restart_replay_probe.gd"

$focusedMatch = [regex]::Match($focused, 'ECO\.PH5 reference_description_hash=([0-9a-f]{64}) profile_matrix_hash=([0-9a-f]{64}) full_materialization_hash=([0-9a-f]{64})')
$restartMatch = [regex]::Match($restart, 'reference_description_hash=([0-9a-f]{64}) profile_matrix_hash=([0-9a-f]{64}) full_materialization_hash=([0-9a-f]{64})')
if (-not $focusedMatch.Success) { throw "Unable to parse PH5 focused hashes" }
if (-not $restartMatch.Success) { throw "Unable to parse PH5 restart hashes" }
for ($i = 1; $i -le 3; $i++) {
    if ($focusedMatch.Groups[$i].Value -ne $restartMatch.Groups[$i].Value) {
        throw "ECO.PH5 REPLAY_DIVERGENCE: focused/restart hash group $i mismatch"
    }
}

Write-Host "ECO.PH4 parent lifecycle: PASS (718 assertions + restart 5)"
Write-Host "ECO.PH5 focused acceptance: PASS"
Write-Host "ECO.PH5 visual lab smoke: PASS"
Write-Host "ECO.PH5 restart replay: PASS"
Write-Host "ECO.PH5 reference_description_hash=$($focusedMatch.Groups[1].Value)"
Write-Host "ECO.PH5 profile_matrix_hash=$($focusedMatch.Groups[2].Value)"
Write-Host "ECO.PH5 full_materialization_hash=$($focusedMatch.Groups[3].Value)"
Write-Host "ECO.PH5 extensible procedural visual materialization candidate: PASS"
