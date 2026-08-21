param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP32 = "172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$P32ValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-2-density-carrying-capacity-validation.json"
if (-not (Test-Path -LiteralPath $P32ValidationPath -PathType Leaf)) { throw "P3.2 validation file not found: $P32ValidationPath" }
$p32Validation = Get-Content -LiteralPath $P32ValidationPath -Raw | ConvertFrom-Json
$p32Status = [string]$p32Validation.status
if (-not $p32Status.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.2 parent is not ACCEPTED: status=$p32Status"
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
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    return ($output -join "`n")
}

Invoke-Godot "ECO P3.3 parser/preload preflight" "res://tests/research/ecology/eco_p3_3_spatial_dispersal_acceptance.gd" -CheckOnly | Out-Null

Write-Host "=== ECO P3.2 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P3_2_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P3.2 accepted parent regression failed" }

$runA = Invoke-Godot "ECO P3.3 spatial dispersal A" "res://tests/research/ecology/eco_p3_3_spatial_dispersal_acceptance.gd"
$runB = Invoke-Godot "ECO P3.3 spatial dispersal fresh process B" "res://tests/research/ecology/eco_p3_3_spatial_dispersal_acceptance.gd"

$hashA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$hashB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p3_2=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p3_2=([0-9a-f]{64})')
foreach ($m in @($hashA, $hashB, $parentA, $parentB)) {
    if (-not $m.Success) { throw "Unable to parse P3.3 canonical output" }
}
if ($hashA.Groups[1].Value -ne $hashB.Groups[1].Value) { throw "P3.3 fresh-process aggregate hash mismatch" }
if ($parentA.Groups[1].Value -ne $ExpectedParentP32 -or $parentB.Groups[1].Value -ne $ExpectedParentP32) { throw "P3.3 P3.2 parent identity mismatch" }

Write-Host "ECO.P3.2 accepted parent regression: PASS"
Write-Host "ECO.P3.3 spatial dispersal fresh-process determinism: PASS"
Write-Host "ECO.P3.3 aggregate_hash=$($hashA.Groups[1].Value)"
Write-Host "ECO.P3.3 parent_p3_2=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.3 candidate automated gates: PASS"
