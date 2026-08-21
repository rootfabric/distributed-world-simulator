param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE23 = "82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8"
$ExpectedParentE23Head = "c7ee41371807ed7dbb75e7e1eae1587105873a26"
$ExpectedBake = "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
$ExpectedCatalog = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$ExpectedAggregate = "ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5"
$ExpectedPlan = "f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0"
$TestScript = "res://tests/research/ecology/eco_evo2_e2_4_environment_generalization_matrix_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical E2.4 runner requires a clean checkout" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$E23Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-3-frozen-catalog-transfer-validation.json"
if (-not (Test-Path -LiteralPath $E23Path -PathType Leaf)) { throw "E2.3 validation file not found: $E23Path" }
$e23 = Get-Content -LiteralPath $E23Path -Raw | ConvertFrom-Json
if (-not ([string]$e23.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.3 parent is not ACCEPTED" }
if ([string]$e23.acceptance.aggregate_hash -ne $ExpectedParentE23) { throw "E2.3 accepted aggregate mismatch" }
if ([string]$e23.acceptance.code_under_test_head -ne $ExpectedParentE23Head) { throw "E2.3 accepted code-under-test mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_disturbance_recovery_v1.gd" = "ad50faf267583992e2a5c972b434a2520fd29f17"
    "scripts/research/ecology/plant_establishment_seed_bank_v1.gd" = "493566ee8ccbc6c0fac63310f0e6d6b9e3bb982d"
    "scripts/research/ecology/plant_evolution_bake_export_v1.gd" = "6ed4abfa58c28a99fb1c28547d81e1a292756e10"
    "scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd" = "a886d179fe32a2bb531956923fd0cc59bbbb28c6"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_lifecycle_payoff_v1.gd" = "5004b2d32806149e7cb544b21286181ab2217fb3"
    "scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd" = "fdb7d4cbacc7dd575c665c66340a926f82f07483"
    "scripts/research/ecology/plant_local_population_succession_v1.gd" = "2f0d67e8db1a841c085f574bc7f725479a83b39d"
    "scripts/research/ecology/plant_long_horizon_biogeography_v1.gd" = "87de6aac3bb9046f53da0a4f8d02c9446983ddb9"
    "scripts/research/ecology/plant_patch_migration_v1.gd" = "58dc4c5cecd4a1fd41740c79010bb357395c6807"
    "scripts/research/ecology/plant_recruitment_traits_v1.gd" = "6faeff9da9f7fa5a03e1df586de9cb29795d30de"
    "scripts/research/ecology/plant_resource_model_v1.gd" = "26fd4118307f098bd85b6d4b953a27ad8b9d85cd"
    "scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd" = "151937ac24818dc792c6ac0abf298507e80c231d"
    "scripts/research/ecology/plant_species_catalog_v1.gd" = "f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2"
    "scripts/research/ecology/single_plant_patch_simulator_v1.gd" = "068c8aaa47e17d924d741a044a059df18ad0ed25"
    "scripts/research/ecology/plant_environment_generalization_matrix_v1.gd" = "823ef6445d7f71aee79b7c0bb0932b321f90ce8d"
    "tests/research/ecology/eco_evo2_e2_4_environment_generalization_matrix_acceptance.gd" = "e365aafe7cb703d6cc26e812b8e1ea0c7716de35"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "E2.4 closure file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "E2.4 exact closure mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 E2.4 exact transitive executable closure: PASS (18/18)"

Write-Host "=== ECO EVO2 E2.4 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.4 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.4 parser/preload emitted Godot ERROR output" }

function Invoke-E24([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.4 Environment Generalization Matrix: PASS \(82 assertions\)') { throw "$Label did not emit E2.4 PASS marker" }
    return $joined
}

$runA = Invoke-E24 "ECO EVO2 E2.4 environment matrix A"
$runB = Invoke-E24 "ECO EVO2 E2.4 environment matrix fresh process B"
if ($runA -ne $runB) { throw "E2.4 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.4 $Name" }
    return $m.Groups[1].Value
}
$aggregate = Parse-Hash $runA "aggregate_hash"
$plan = Parse-Hash $runA "plan_hash"
$parent = Parse-Hash $runA "parent_e2_3"
$bake = Parse-Hash $runA "bake_hash"
$catalog = Parse-Hash $runA "catalog_hash"
if ($aggregate -ne $ExpectedAggregate) { throw "E2.4 aggregate mismatch" }
if ($plan -ne $ExpectedPlan) { throw "E2.4 plan hash mismatch" }
if ($parent -ne $ExpectedParentE23) { throw "E2.4 parent E2.3 mismatch" }
if ($bake -ne $ExpectedBake) { throw "E2.4 frozen bake mismatch" }
if ($catalog -ne $ExpectedCatalog) { throw "E2.4 frozen catalog mismatch" }
if ($runA -notmatch '(?m)^phase_patch_isolated_static=VALID_NO_COLONIZATION\|-1\|[0-9a-f]{64}$') { throw "E2.4 isolated causal control marker missing" }
foreach ($cell in @("near_source","dry","wet","nutrient_poor","high_seasonality","patch_isolated")) {
    if ($runA -notmatch "(?m)^cell_${cell}_hash=[0-9a-f]{64}$") { throw "E2.4 cell hash missing: $cell" }
}

Write-Host "ECO.EVO2 E2.4 E2.3 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.4 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.4 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.4 aggregate_hash=$aggregate"
Write-Host "ECO.EVO2 E2.4 plan_hash=$plan"
Write-Host "ECO.EVO2 E2.4 candidate automated gates: PASS"
