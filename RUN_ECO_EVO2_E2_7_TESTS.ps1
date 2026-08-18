param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE26 = "1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd"
$ExpectedParentE26Head = "8ac37bfea0f36731407e1252db1a7c2a2305420e"
$ExpectedParentE26ReplicateSet = "5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637"
$ExpectedAggregate = "eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d"
$ExpectedSeedEnsemble = "a49ce9d6856e08e1e0a61f060a8019de61685cdc63b25229b3761c9e7c9d792f"
$ExpectedDryAggregate = "f3b65f8c890c75243f9a089f6f3036ef937c7251d675c0fd6919f06b00522c3f"
$ExpectedWetAggregate = "98020ab8f6bb8fb52775ac4796bc2f45ea16530e468c5324b5716f598af4989b"
$TestScript = "res://tests/research/ecology/eco_evo2_e2_7_cross_seed_robustness_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical E2.7 runner requires a clean checkout" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne "4.7.1.stable.double.custom_build.a13da4feb") { throw "GODOT_IDENTITY_MISMATCH: $version" }

$E26Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-6-replicated-causal-experiments-validation.json"
if (-not (Test-Path -LiteralPath $E26Path -PathType Leaf)) { throw "E2.6 validation file not found: $E26Path" }
$e26 = Get-Content -LiteralPath $E26Path -Raw | ConvertFrom-Json
if (-not ([string]$e26.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.6 parent is not ACCEPTED" }
if ([string]$e26.acceptance.aggregate_hash -ne $ExpectedParentE26) { throw "E2.6 accepted aggregate mismatch" }
if ([string]$e26.acceptance.code_under_test_head -ne $ExpectedParentE26Head) { throw "E2.6 accepted code-under-test mismatch" }
if ([string]$e26.frozen_outputs.replicate_set_hash -ne $ExpectedParentE26ReplicateSet) { throw "E2.6 accepted replicate-set mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_lineage_record_v1.gd" = "0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0"
    "scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd" = "7b9b5d41236cb27256dd7405201436a71a3eafea"
    "scripts/research/ecology/plant_resource_model_v1.gd" = "26fd4118307f098bd85b6d4b953a27ad8b9d85cd"
    "scripts/research/ecology/plant_cross_seed_robustness_v1.gd" = "f980a6132835cd2c483d5210615579ddccf7e618"
    "scripts/research/ecology/plant_cross_seed_protocol_v1.gd" = "8d28fb09ac6e3f8b46594b39f76db69c2b6f9b17"
    "scripts/research/ecology/plant_cross_seed_evidence_v1.gd" = "940ed657b7aa85758ac33088634d1ce5fdc4e673"
    "tests/research/ecology/eco_evo2_e2_7_cross_seed_robustness_acceptance.gd" = "334a833acd1d0bc32ee03f0977d764ff5e517196"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "E2.7 closure file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "E2.7 exact closure mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 E2.7 exact transitive executable closure: PASS (9/9)"

$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.7 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.7 parser/preload emitted Godot ERROR output" }

function Invoke-E27([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.7 Cross-Seed Robustness: PASS \(290 assertions\)') { throw "$Label did not emit E2.7 PASS marker" }
    return $joined
}

$runA = Invoke-E27 "ECO EVO2 E2.7 cross-seed A"
$runB = Invoke-E27 "ECO EVO2 E2.7 cross-seed fresh process B"
if ($runA -ne $runB) { throw "E2.7 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.7 $Name" }
    return $m.Groups[1].Value
}
function Parse-Int([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9]+)$")
    if (-not $m.Success) { throw "Unable to parse E2.7 $Name" }
    return [int]$m.Groups[1].Value
}
function Parse-Number([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=(-?[0-9]+(?:\.[0-9]+)?)$")
    if (-not $m.Success) { throw "Unable to parse E2.7 $Name" }
    return [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

if ((Parse-Hash $runA "aggregate_hash") -ne $ExpectedAggregate) { throw "E2.7 aggregate mismatch" }
if ((Parse-Hash $runA "parent_e2_6") -ne $ExpectedParentE26) { throw "E2.7 parent aggregate mismatch" }
if ((Parse-Hash $runA "parent_e2_6_head") -ne $ExpectedParentE26Head) { throw "E2.7 parent HEAD mismatch" }
if ((Parse-Hash $runA "parent_e2_6_replicate_set") -ne $ExpectedParentE26ReplicateSet) { throw "E2.7 parent replicate-set mismatch" }
if ((Parse-Hash $runA "seed_ensemble_hash") -ne $ExpectedSeedEnsemble) { throw "E2.7 seed ensemble mismatch" }
if ((Parse-Hash $runA "dry_aggregate_hash") -ne $ExpectedDryAggregate) { throw "E2.7 DRY aggregate mismatch" }
if ((Parse-Hash $runA "wet_aggregate_hash") -ne $ExpectedWetAggregate) { throw "E2.7 WET aggregate mismatch" }
if ((Parse-Int $runA "full_seed_pass_count") -lt 7) { throw "E2.7 full-seed pass threshold failed" }
if ((Parse-Int $runA "dry_positive_count") -lt 8 -or (Parse-Int $runA "wet_positive_count") -lt 8) { throw "E2.7 positive-effect threshold failed" }
if ((Parse-Int $runA "dry_home_count") -lt 8 -or (Parse-Int $runA "wet_home_count") -lt 8) { throw "E2.7 home-advantage threshold failed" }
if ((Parse-Number $runA "dry_q25") -le 0.0 -or (Parse-Number $runA "wet_q25") -le 0.0) { throw "E2.7 lower quartile is not positive" }
if ((Parse-Number $runA "dry_loo_min_mean") -le 0.0 -or (Parse-Number $runA "wet_loo_min_mean") -le 0.0) { throw "E2.7 leave-one-out minimum mean is not positive" }

Write-Host "ECO.EVO2 E2.7 E2.6 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.7 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.7 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.7 cross-seed robustness thresholds: PASS"
Write-Host "ECO.EVO2 E2.7 aggregate_hash=$ExpectedAggregate"
Write-Host "ECO.EVO2 E2.7 candidate automated gates: PASS"
