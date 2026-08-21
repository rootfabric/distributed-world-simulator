param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE25 = "942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6"
$ExpectedParentE25Head = "4c17a91957e392eabc04e136f9590773dbe54dd1"
$ExpectedAggregate = "1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd"
$ExpectedReplicateSet = "5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637"
$ExpectedDryAggregate = "10ca9de3ca7989494507bcb081a410bd1e8e625faa10843f62201c258e9bdd52"
$ExpectedWetAggregate = "3fa2b4a96a141241e367d56b7fa69f6d8bc9f92f32cd5266128248c21a092755"
$ExpectedReplicates = [ordered]@{
    "r01" = "36b5d458d037cafe6c1d72bb68040876a2a453637d68d89de75dae98f9e7fa84"
    "r02" = "c3e2dbc3949c6d16edc646954b1a324b0e03215aae7a1759ec3d79bfd8a64177"
    "r03" = "d808be565e5d1c39725b5212b72e85efb4113f3e11e27dc3f560da515d455477"
    "r04" = "9785a696f335895b48dde1dc2813bde5f872bf887f9664c3ec122dba789c4ca4"
    "r05" = "a815a398caf1845da32ea4fdc7e7462e42e36c4580393bac0b215cbbef71f4f9"
}
$TestScript = "res://tests/research/ecology/eco_evo2_e2_6_replicated_causal_experiments_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical E2.6 runner requires a clean checkout" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$E25Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-5-sorting-vs-adaptation-validation.json"
if (-not (Test-Path -LiteralPath $E25Path -PathType Leaf)) { throw "E2.5 validation file not found: $E25Path" }
$e25 = Get-Content -LiteralPath $E25Path -Raw | ConvertFrom-Json
if (-not ([string]$e25.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.5 parent is not ACCEPTED" }
if ([string]$e25.acceptance.aggregate_hash -ne $ExpectedParentE25) { throw "E2.5 accepted aggregate mismatch" }
if ([string]$e25.acceptance.code_under_test_head -ne $ExpectedParentE25Head) { throw "E2.5 accepted code-under-test mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_lineage_record_v1.gd" = "0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0"
    "scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd" = "7b9b5d41236cb27256dd7405201436a71a3eafea"
    "scripts/research/ecology/plant_resource_model_v1.gd" = "26fd4118307f098bd85b6d4b953a27ad8b9d85cd"
    "scripts/research/ecology/plant_replicated_causal_experiments_v1.gd" = "7fb18d91ba59493c608edafba610dc882152852a"
    "tests/research/ecology/eco_evo2_e2_6_replicated_causal_experiments_acceptance.gd" = "55b9af8b1969b033606fab112accd616eee8122a"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "E2.6 closure file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "E2.6 exact closure mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 E2.6 exact transitive executable closure: PASS (7/7)"

Write-Host "=== ECO EVO2 E2.6 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.6 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.6 parser/preload emitted Godot ERROR output" }

function Invoke-E26([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.6 Replicated Causal Experiments: PASS \(218 assertions\)') { throw "$Label did not emit E2.6 PASS marker" }
    return $joined
}

$runA = Invoke-E26 "ECO EVO2 E2.6 replicated causal experiment A"
$runB = Invoke-E26 "ECO EVO2 E2.6 replicated causal experiment fresh process B"
if ($runA -ne $runB) { throw "E2.6 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.6 $Name" }
    return $m.Groups[1].Value
}
$aggregate = Parse-Hash $runA "aggregate_hash"
$replicateSet = Parse-Hash $runA "replicate_set_hash"
$parent = Parse-Hash $runA "parent_e2_5"
$parentHead = [regex]::Match($runA, '(?m)^parent_e2_5_head=([0-9a-f]{40})$').Groups[1].Value
$dryAggregate = Parse-Hash $runA "dry_aggregate_hash"
$wetAggregate = Parse-Hash $runA "wet_aggregate_hash"
if ($aggregate -ne $ExpectedAggregate) { throw "E2.6 aggregate mismatch" }
if ($replicateSet -ne $ExpectedReplicateSet) { throw "E2.6 replicate-set mismatch" }
if ($parent -ne $ExpectedParentE25) { throw "E2.6 parent E2.5 mismatch" }
if ($parentHead -ne $ExpectedParentE25Head) { throw "E2.6 parent E2.5 head mismatch" }
if ($dryAggregate -ne $ExpectedDryAggregate) { throw "E2.6 DRY aggregate mismatch" }
if ($wetAggregate -ne $ExpectedWetAggregate) { throw "E2.6 WET aggregate mismatch" }
if ($runA -notmatch '(?m)^dry_positive_count=5$' -or $runA -notmatch '(?m)^wet_positive_count=5$') { throw "E2.6 positive replicate count drift" }
if ($runA -notmatch '(?m)^dry_home_advantage_count=5$' -or $runA -notmatch '(?m)^wet_home_advantage_count=5$') { throw "E2.6 home-advantage replicate count drift" }
foreach ($entry in $ExpectedReplicates.GetEnumerator()) {
    $actual = Parse-Hash $runA ("replicate_{0}_hash" -f $entry.Key)
    if ($actual -ne $entry.Value) { throw "E2.6 replicate hash mismatch: $($entry.Key)" }
}

Write-Host "ECO.EVO2 E2.6 E2.5 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.6 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.6 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.6 all-replicates-retained gate: PASS (5/5)"
Write-Host "ECO.EVO2 E2.6 aggregate_hash=$aggregate"
Write-Host "ECO.EVO2 E2.6 replicate_set_hash=$replicateSet"
Write-Host "ECO.EVO2 E2.6 candidate automated gates: PASS"
