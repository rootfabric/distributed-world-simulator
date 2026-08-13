param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP36 = "a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc"
$ExpectedAggregate = "ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$ParentValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-6-disturbance-succession-validation.json"
if (-not (Test-Path -LiteralPath $ParentValidationPath -PathType Leaf)) { throw "P3.6 validation file not found: $ParentValidationPath" }
$parentValidation = Get-Content -LiteralPath $ParentValidationPath -Raw | ConvertFrom-Json
$parentStatus = [string]$parentValidation.status
if (-not $parentStatus.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.6 parent is not ACCEPTED: status=$parentStatus"
}

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

Invoke-Godot "ECO P3.7 parser/preload preflight" "res://tests/research/ecology/eco_p3_7_multi_niche_coexistence_acceptance.gd" -CheckOnly | Out-Null
Write-Host "=== ECO P3.6 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P3_6_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P3.6 accepted parent regression failed" }
$runA = Invoke-Godot "ECO P3.7 multi-niche coexistence A" "res://tests/research/ecology/eco_p3_7_multi_niche_coexistence_acceptance.gd"
$runB = Invoke-Godot "ECO P3.7 multi-niche coexistence fresh process B" "res://tests/research/ecology/eco_p3_7_multi_niche_coexistence_acceptance.gd"
$hashA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$hashB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p3_6=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p3_6=([0-9a-f]{64})')
foreach ($m in @($hashA,$hashB,$parentA,$parentB)) { if (-not $m.Success) { throw "Unable to parse P3.7 canonical output" } }
if ($hashA.Groups[1].Value -ne $hashB.Groups[1].Value) { throw "P3.7 fresh-process aggregate hash mismatch" }
if ($hashA.Groups[1].Value -ne $ExpectedAggregate) { throw "P3.7 aggregate identity mismatch: expected=$ExpectedAggregate actual=$($hashA.Groups[1].Value)" }
if ($parentA.Groups[1].Value -ne $ExpectedParentP36 -or $parentB.Groups[1].Value -ne $ExpectedParentP36) { throw "P3.7 P3.6 parent identity mismatch" }
Write-Host "ECO.P3.6 accepted parent regression: PASS"
Write-Host "ECO.P3.7 multi-niche coexistence fresh-process determinism: PASS"
Write-Host "ECO.P3.7 aggregate_hash=$($hashA.Groups[1].Value)"
Write-Host "ECO.P3.7 parent_p3_6=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.7 candidate automated gates: PASS"
