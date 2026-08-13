param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParent = "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"
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

Invoke-Godot "ECO P3.1 parser/preload preflight" "res://tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd" -CheckOnly | Out-Null

Write-Host "=== ECO EVO1 P2.8 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_EVO1_P2_8_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P2.8 accepted parent regression failed" }

$runA = Invoke-Godot "ECO P3.1 resource competition A" "res://tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd"
$runB = Invoke-Godot "ECO P3.1 resource competition fresh process B" "res://tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd"

$hashA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$hashB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p2_8=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p2_8=([0-9a-f]{64})')
foreach ($m in @($hashA, $hashB, $parentA, $parentB)) {
    if (-not $m.Success) { throw "Unable to parse P3.1 canonical output" }
}
if ($hashA.Groups[1].Value -ne $hashB.Groups[1].Value) { throw "P3.1 fresh-process aggregate hash mismatch" }
if ($parentA.Groups[1].Value -ne $ExpectedParent -or $parentB.Groups[1].Value -ne $ExpectedParent) { throw "P3.1 P2.8 parent identity mismatch" }

Write-Host "ECO.EVO1-P2.8 accepted parent regression: PASS"
Write-Host "ECO.P3.1 resource competition fresh-process determinism: PASS"
Write-Host "ECO.P3.1 aggregate_hash=$($hashA.Groups[1].Value)"
Write-Host "ECO.P3.1 parent_p2_8=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.1 candidate automated gates: PASS"
