param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentP27 = "7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$ParentValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-8-deterministic-ecosystem-persistence-validation.json"
if (-not (Test-Path -LiteralPath $ParentValidationPath -PathType Leaf)) {
    throw "P3.8 validation file not found: $ParentValidationPath"
}
$parentValidation = Get-Content -LiteralPath $ParentValidationPath -Raw | ConvertFrom-Json
$parentStatus = [string]$parentValidation.status
if (-not $parentStatus.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P3.8 parent is not ACCEPTED: status=$parentStatus"
}
$parentP27 = [string]$parentValidation.frozen_full_exact_godot_evidence.parent_p3_7
if ($parentP27 -ne $ExpectedParentP27) {
    throw "P3.8 ancestry does not pin expected accepted P2.7/P3.7 lineage evidence: expected=$ExpectedParentP27 actual=$parentP27"
}

function Invoke-Godot([string]$Label) {
    Write-Host "=== $Label ==="
    $previousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $output = & $GodotPath --headless --path $RootDir --script res://tests/research/ecology/eco_evo2_e2_1_species_catalog_acceptance.gd 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousBreakpoint) {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
        else {
            $env:BREAKPOINT_RUNTIME_DISABLED = $previousBreakpoint
        }
    }
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.1 SpeciesCatalog Contract: PASS') {
        throw "$Label did not emit E2.1 PASS marker"
    }
    return $joined
}

Write-Host "=== ECO EVO2 E2.1 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/research/ecology/eco_evo2_e2_1_species_catalog_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.1 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.1 parser/preload preflight emitted Godot ERROR output" }

$runA = Invoke-Godot "ECO EVO2 E2.1 SpeciesCatalog A"
$runB = Invoke-Godot "ECO EVO2 E2.1 SpeciesCatalog fresh process B"
if ($runA -ne $runB) { throw "E2.1 fresh-process logs are not byte-identical" }

$aggregateA = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$aggregateB = [regex]::Match($runB, 'aggregate_hash=([0-9a-f]{64})')
$single = [regex]::Match($runA, 'single_catalog_hash=([0-9a-f]{64})')
$multi = [regex]::Match($runA, 'multi_catalog_hash=([0-9a-f]{64})')
$species = [regex]::Match($runA, 'alpha_research_species_id=(eco-research-species/[0-9a-f]{24})')
$parent = [regex]::Match($runA, 'parent_p2_7=([0-9a-f]{64})')
foreach ($match in @($aggregateA, $aggregateB, $single, $multi, $species, $parent)) {
    if (-not $match.Success) { throw "Unable to parse E2.1 canonical output" }
}
if ($aggregateA.Groups[1].Value -ne $aggregateB.Groups[1].Value) {
    throw "E2.1 fresh-process aggregate mismatch"
}
if ($parent.Groups[1].Value -ne $ExpectedParentP27) {
    throw "E2.1 parent identity mismatch"
}

Write-Host "ECO.EVO2 E2.1 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.1 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.1 aggregate_hash=$($aggregateA.Groups[1].Value)"
Write-Host "ECO.EVO2 E2.1 single_catalog_hash=$($single.Groups[1].Value)"
Write-Host "ECO.EVO2 E2.1 multi_catalog_hash=$($multi.Groups[1].Value)"
Write-Host "ECO.EVO2 E2.1 alpha_research_species_id=$($species.Groups[1].Value)"
Write-Host "ECO.EVO2 E2.1 parent_p2_7=$($parent.Groups[1].Value)"
Write-Host "ECO.EVO2 E2.1 candidate automated gates: PASS"
