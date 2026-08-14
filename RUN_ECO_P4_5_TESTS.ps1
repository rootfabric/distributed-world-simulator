param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP44 = "4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2"
$ExpectedP44KernelBlob = "2f4d7809a84d4f6d23a3f113c23b359f0803d564"
$ExpectedP44TestBlob = "2385b035082834aaae1eb91e25aa798c26ca40dc"
$ExpectedP44RunnerBlob = "7dc69caf556f36ac4e282acb5713f3d072e63ad5"
$ExpectedKernelBlob = "2a4083fb9d4b55f8c16421c4f3555c19a952711f"
$ExpectedTestBlob = "041e7e81588f59b54bac76d7cd9ad558d054b0de"
$ExpectedAggregate = "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"
$ExpectedSourceOwnership = "f89f476285a40fdf0fe0f79557001f536fff4df2c8da9085cd5ecffce314d1de"
$ExpectedHandoff = "3d9e94ffddc7f9cf3f6e765c08b620a2bf3436b751fbadcedb694fe5c9e2624c"
$ExpectedTargetOwnership = "b7d0edb5c943dbe0f1ba62066dd94c5a5d84eff82177897174ba37f984b734c4"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-4-production-persistence-validation.json"
if (-not (Test-Path -LiteralPath $parentValidationPath -PathType Leaf)) { throw "P4.4 validation missing" }
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$parentValidation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.4 parent is not ACCEPTED: status=$($parentValidation.status)"
}
$parentAggregate = ""
if ($null -ne $parentValidation.acceptance_evidence -and $null -ne $parentValidation.acceptance_evidence.aggregate_hash) {
    $parentAggregate = [string]$parentValidation.acceptance_evidence.aggregate_hash
} elseif ($null -ne $parentValidation.full_chain_expected -and $null -ne $parentValidation.full_chain_expected.aggregate_hash) {
    $parentAggregate = [string]$parentValidation.full_chain_expected.aggregate_hash
}
if ($parentAggregate -ne $ExpectedParentP44) { throw "P4.4 accepted aggregate mismatch: expected=$ExpectedParentP44 actual=$parentAggregate" }

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_region_persistence_v1.gd" $ExpectedP44KernelBlob
Assert-Blob "tests/ecology/production/eco_p4_4_region_persistence_acceptance.gd" $ExpectedP44TestBlob
Assert-Blob "RUN_ECO_P4_4_TESTS.ps1" $ExpectedP44RunnerBlob
Assert-Blob "scripts/ecology/production/ecology_region_ownership_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_5_region_ownership_acceptance.gd" $ExpectedTestBlob

Write-Host "=== ECO P4.5 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/ecology/production/eco_p4_5_region_ownership_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P4.5 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P4.5 parser/preload emitted Godot ERROR output" }

Write-Host "=== ECO P4.4 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P4_4_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P4.4 accepted parent regression failed" }

function Invoke-P45([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script res://tests/ecology/production/eco_p4_5_region_ownership_acceptance.gd 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

$runA = Invoke-P45 "ECO P4.5 region ownership A"
$runB = Invoke-P45 "ECO P4.5 region ownership fresh process B"
if ($runA -ne $runB) { throw "P4.5 fresh-process logs are not byte-identical" }

$aggregate = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$source = [regex]::Match($runA, 'source_ownership_hash=([0-9a-f]{64})')
$handoff = [regex]::Match($runA, 'handoff_hash=([0-9a-f]{64})')
$target = [regex]::Match($runA, 'target_ownership_hash=([0-9a-f]{64})')
$parent = [regex]::Match($runA, 'parent_p4_4=([0-9a-f]{64})')
foreach ($match in @($aggregate,$source,$handoff,$target,$parent)) {
    if (-not $match.Success) { throw "Unable to parse P4.5 canonical output" }
}
if ($aggregate.Groups[1].Value -ne $ExpectedAggregate) { throw "P4.5 aggregate mismatch" }
if ($source.Groups[1].Value -ne $ExpectedSourceOwnership) { throw "P4.5 source ownership mismatch" }
if ($handoff.Groups[1].Value -ne $ExpectedHandoff) { throw "P4.5 handoff hash mismatch" }
if ($target.Groups[1].Value -ne $ExpectedTargetOwnership) { throw "P4.5 target ownership mismatch" }
if ($parent.Groups[1].Value -ne $ExpectedParentP44) { throw "P4.5 parent P4.4 mismatch" }

Write-Host "ECO.P4.4 accepted parent regression: PASS"
Write-Host "ECO.P4.5 region ownership / server handoff fresh-process determinism: PASS"
Write-Host "ECO.P4.5 aggregate_hash=$($aggregate.Groups[1].Value)"
Write-Host "ECO.P4.5 source_ownership_hash=$($source.Groups[1].Value)"
Write-Host "ECO.P4.5 handoff_hash=$($handoff.Groups[1].Value)"
Write-Host "ECO.P4.5 target_ownership_hash=$($target.Groups[1].Value)"
Write-Host "ECO.P4.5 parent_p4_4=$($parent.Groups[1].Value)"
Write-Host "ECO.P4.5 candidate automated gates: PASS"
