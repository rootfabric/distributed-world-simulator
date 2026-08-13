param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP34 = "a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813"
$ExpectedAggregate = "255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$P34ValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-4-environmental-gradient-validation.json"
if (-not (Test-Path -LiteralPath $P34ValidationPath -PathType Leaf)) { throw "P3.4 validation file not found: $P34ValidationPath" }
$p34Validation = Get-Content -LiteralPath $P34ValidationPath -Raw | ConvertFrom-Json
$p34Status = [string]$p34Validation.status
if (-not $p34Status.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.4 parent is not ACCEPTED: status=$p34Status"
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

Invoke-Godot "ECO P3.5 parser/preload preflight" "res://tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd" -CheckOnly | Out-Null

Write-Host "=== ECO P3.4 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P3_4_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P3.4 accepted parent regression failed" }

$runA = Invoke-Godot "ECO P3.5 seasonal world A" "res://tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd"
$runB = Invoke-Godot "ECO P3.5 seasonal world fresh process B" "res://tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd"

$hashA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$hashB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p3_4=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p3_4=([0-9a-f]{64})')
foreach ($m in @($hashA, $hashB, $parentA, $parentB)) {
    if (-not $m.Success) { throw "Unable to parse P3.5 canonical output" }
}
if ($hashA.Groups[1].Value -ne $hashB.Groups[1].Value) { throw "P3.5 fresh-process aggregate hash mismatch" }
if ($hashA.Groups[1].Value -ne $ExpectedAggregate) { throw "P3.5 aggregate identity mismatch: expected=$ExpectedAggregate actual=$($hashA.Groups[1].Value)" }
if ($parentA.Groups[1].Value -ne $ExpectedParentP34 -or $parentB.Groups[1].Value -ne $ExpectedParentP34) { throw "P3.5 P3.4 parent identity mismatch" }

Write-Host "ECO.P3.4 accepted parent regression: PASS"
Write-Host "ECO.P3.5 seasonal world fresh-process determinism: PASS"
Write-Host "ECO.P3.5 aggregate_hash=$($hashA.Groups[1].Value)"
Write-Host "ECO.P3.5 parent_p3_4=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.5 candidate automated gates: PASS"
