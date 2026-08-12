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

Write-Host "=== ECO PH5-S2 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_PH5_S2_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "PH5-S2 parent regression failed" }

$s3Policy = Invoke-GodotScript "ECO PH5-S3 tier policy" "res://tests/research/ecology/eco_ph5_s3_multiscale_acceptance.gd"
$s3Far = Invoke-GodotScript "ECO PH5-S3 canopy/impostor materialization" "res://tests/research/ecology/eco_ph5_s3_far_materialization_smoke.gd"
$s3Materialization = Invoke-GodotScript "ECO PH5-S3 real multiscale materialization" "res://tests/research/ecology/eco_ph5_s3_multiscale_materialization_acceptance.gd"
$s4Robustness = Invoke-GodotScript "ECO PH5-S4 representation robustness" "res://tests/research/ecology/eco_ph5_s4_representation_robustness.gd"
$s4Matrix = Invoke-GodotScript "ECO PH5-S4 contrasting phenotype x tier matrix" "res://tests/research/ecology/eco_ph5_s4_multiscale_matrix_acceptance.gd"
$s4Smoke = Invoke-GodotScript "ECO PH5-S4 multiscale graphical lab smoke" "res://tests/research/ecology/eco_ph5_s4_multiscale_visual_lab_smoke.gd"

$materializationMatch = [regex]::Match($s3Materialization, 'matrix_hash=([0-9a-f]{64})')
$robustnessMatch = [regex]::Match($s4Robustness, 'digest=([0-9a-f]{64})')
$matrixMatch = [regex]::Match($s4Matrix, 'matrix_hash=([0-9a-f]{64})')
if (-not $materializationMatch.Success) { throw "Unable to parse PH5-S3 materialization matrix hash" }
if (-not $robustnessMatch.Success) { throw "Unable to parse PH5-S4 robustness digest" }
if (-not $matrixMatch.Success) { throw "Unable to parse PH5-S4 phenotype/tier matrix hash" }

Write-Host "ECO.PH5-S3 tier policy: PASS"
Write-Host "ECO.PH5-S3 canopy/impostor materialization: PASS"
Write-Host "ECO.PH5-S3 real multiscale materialization: PASS"
Write-Host "ECO.PH5-S4 robustness: PASS"
Write-Host "ECO.PH5-S4 contrasting phenotype x tier matrix: PASS"
Write-Host "ECO.PH5-S4 visual lab smoke: PASS"
Write-Host "ECO.PH5-S3 materialization_matrix_hash=$($materializationMatch.Groups[1].Value)"
Write-Host "ECO.PH5-S4 robustness_digest=$($robustnessMatch.Groups[1].Value)"
Write-Host "ECO.PH5-S4 phenotype_tier_matrix_hash=$($matrixMatch.Groups[1].Value)"
Write-Host "ECO.PH5-S3/S4 automated candidate gates: PASS"
