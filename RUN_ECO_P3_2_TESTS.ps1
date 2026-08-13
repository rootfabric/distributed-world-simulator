param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP31 = "f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a"
$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$P31ValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-1-resource-competition-validation.json"
if (-not (Test-Path -LiteralPath $P31ValidationPath -PathType Leaf)) { throw "P3.1 validation file not found: $P31ValidationPath" }
$p31Validation = Get-Content -LiteralPath $P31ValidationPath -Raw | ConvertFrom-Json
$p31Status = [string]$p31Validation.status
if (-not $p31Status.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.1 parent is not ACCEPTED: status=$p31Status"
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

Invoke-Godot "ECO P3.2 parser/preload preflight" "res://tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd" -CheckOnly | Out-Null

Write-Host "=== ECO P3.1 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P3_1_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P3.1 accepted parent regression failed" }

$runA = Invoke-Godot "ECO P3.2 density/carrying capacity A" "res://tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd"
$runB = Invoke-Godot "ECO P3.2 density/carrying capacity fresh process B" "res://tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd"

$hashA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$hashB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$parentA = [regex]::Match($runA, 'parent_p3_1=([0-9a-f]{64})')
$parentB = [regex]::Match($runB, 'parent_p3_1=([0-9a-f]{64})')
foreach ($m in @($hashA, $hashB, $parentA, $parentB)) {
    if (-not $m.Success) { throw "Unable to parse P3.2 canonical output" }
}
if ($hashA.Groups[1].Value -ne $hashB.Groups[1].Value) { throw "P3.2 fresh-process aggregate hash mismatch" }
if ($parentA.Groups[1].Value -ne $ExpectedParentP31 -or $parentB.Groups[1].Value -ne $ExpectedParentP31) { throw "P3.2 P3.1 parent identity mismatch" }

Write-Host "ECO.P3.1 accepted parent regression: PASS"
Write-Host "ECO.P3.2 density/carrying capacity fresh-process determinism: PASS"
Write-Host "ECO.P3.2 aggregate_hash=$($hashA.Groups[1].Value)"
Write-Host "ECO.P3.2 parent_p3_1=$($parentA.Groups[1].Value)"
Write-Host "ECO.P3.2 candidate automated gates: PASS"
