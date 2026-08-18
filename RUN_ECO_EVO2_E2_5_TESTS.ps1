param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE24 = "ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5"
$ExpectedParentE24Head = "0135aee461a107375cdb3e52e07e8c799145998b"
$ExpectedParentE24Plan = "f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0"
$ExpectedBake = "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
$ExpectedCatalog = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$ExpectedAggregate = "942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6"
$ExpectedControlPolicy = "0e6481175af3658b2673a612717dd850b917ec5156260b37bd9ee29a9789dc4e"
$ExpectedTreatmentPolicy = "e2927ce7a8f6b3ab5f3d4942a2cc70ca3794e0d67c3e770e0301748967c14416"
$ExpectedDryPair = "1d8dd8f37ad0c83f439dce5493c59b38a3618f9201630a125a6197691eecab7c"
$ExpectedWetPair = "9234fdfa74530c1f16b90960814e88e6417b2f3f9a92a8523e825471f2dd1292"
$TestScript = "res://tests/research/ecology/eco_evo2_e2_5_sorting_vs_adaptation_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical E2.5 runner requires a clean checkout" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$E24Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-4-environment-generalization-matrix-validation.json"
if (-not (Test-Path -LiteralPath $E24Path -PathType Leaf)) { throw "E2.4 validation file not found: $E24Path" }
$e24 = Get-Content -LiteralPath $E24Path -Raw | ConvertFrom-Json
if (-not ([string]$e24.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.4 parent is not ACCEPTED" }
if ([string]$e24.acceptance.aggregate_hash -ne $ExpectedParentE24) { throw "E2.4 accepted aggregate mismatch" }
if ([string]$e24.acceptance.code_under_test_head -ne $ExpectedParentE24Head) { throw "E2.4 accepted code-under-test mismatch" }
if ([string]$e24.frozen_outputs.plan_hash -ne $ExpectedParentE24Plan) { throw "E2.4 accepted plan mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_disturbance_recovery_v1.gd" = "ad50faf267583992e2a5c972b434a2520fd29f17"
    "scripts/research/ecology/plant_environment_generalization_matrix_v1.gd" = "823ef6445d7f71aee79b7c0bb0932b321f90ce8d"
    "scripts/research/ecology/plant_establishment_seed_bank_v1.gd" = "493566ee8ccbc6c0fac63310f0e6d6b9e3bb982d"
    "scripts/research/ecology/plant_evolution_bake_export_v1.gd" = "6ed4abfa58c28a99fb1c28547d81e1a292756e10"
    "scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd" = "a886d179fe32a2bb531956923fd0cc59bbbb28c6"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_lifecycle_payoff_v1.gd" = "5004b2d32806149e7cb544b21286181ab2217fb3"
    "scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd" = "fdb7d4cbacc7dd575c665c66340a926f82f07483"
    "scripts/research/ecology/plant_lineage_record_v1.gd" = "0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0"
    "scripts/research/ecology/plant_local_population_succession_v1.gd" = "2f0d67e8db1a841c085f574bc7f725479a83b39d"
    "scripts/research/ecology/plant_long_horizon_biogeography_v1.gd" = "87de6aac3bb9046f53da0a4f8d02c9446983ddb9"
    "scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd" = "7b9b5d41236cb27256dd7405201436a71a3eafea"
    "scripts/research/ecology/plant_patch_migration_v1.gd" = "58dc4c5cecd4a1fd41740c79010bb357395c6807"
    "scripts/research/ecology/plant_recruitment_traits_v1.gd" = "6faeff9da9f7fa5a03e1df586de9cb29795d30de"
    "scripts/research/ecology/plant_resource_model_v1.gd" = "26fd4118307f098bd85b6d4b953a27ad8b9d85cd"
    "scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd" = "151937ac24818dc792c6ac0abf298507e80c231d"
    "scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd" = "74443f7b0c1b5e2234b1949761abc6cfab4bdd9c"
    "scripts/research/ecology/plant_species_catalog_v1.gd" = "f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2"
    "scripts/research/ecology/single_plant_patch_simulator_v1.gd" = "068c8aaa47e17d924d741a044a059df18ad0ed25"
    "tests/research/ecology/eco_evo2_e2_5_sorting_vs_adaptation_acceptance.gd" = "3b2dca9fd3f15750da7a3b200ce800371f6d2021"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "E2.5 closure file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "E2.5 exact closure mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 E2.5 exact transitive executable closure: PASS (21/21)"

Write-Host "=== ECO EVO2 E2.5 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.5 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.5 parser/preload emitted Godot ERROR output" }

function Invoke-E25([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.5 Ecological Sorting vs Continued Adaptation: PASS \(93 assertions\)') { throw "$Label did not emit E2.5 PASS marker" }
    return $joined
}

$runA = Invoke-E25 "ECO EVO2 E2.5 sorting-vs-adaptation A"
$runB = Invoke-E25 "ECO EVO2 E2.5 sorting-vs-adaptation fresh process B"
if ($runA -ne $runB) { throw "E2.5 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.5 $Name" }
    return $m.Groups[1].Value
}
function Parse-Number([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=(-?[0-9]+(?:\.[0-9]+)?)$")
    if (-not $m.Success) { throw "Unable to parse E2.5 $Name" }
    return [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

$aggregate = Parse-Hash $runA "aggregate_hash"
$parent = Parse-Hash $runA "parent_e2_4"
$parentHead = Parse-Hash $runA "parent_e2_4_head"
$parentPlan = Parse-Hash $runA "parent_e2_4_plan"
$bake = Parse-Hash $runA "bake_hash"
$catalog = Parse-Hash $runA "catalog_hash"
$controlPolicy = Parse-Hash $runA "control_policy_hash"
$treatmentPolicy = Parse-Hash $runA "treatment_policy_hash"
$dryPair = Parse-Hash $runA "cell_dry_hash"
$wetPair = Parse-Hash $runA "cell_wet_hash"
if ($aggregate -ne $ExpectedAggregate) { throw "E2.5 aggregate mismatch" }
if ($parent -ne $ExpectedParentE24 -or $parentHead -ne $ExpectedParentE24Head -or $parentPlan -ne $ExpectedParentE24Plan) { throw "E2.5 E2.4 parent mismatch" }
if ($bake -ne $ExpectedBake -or $catalog -ne $ExpectedCatalog) { throw "E2.5 frozen E2.2 identity mismatch" }
if ($controlPolicy -ne $ExpectedControlPolicy -or $treatmentPolicy -ne $ExpectedTreatmentPolicy) { throw "E2.5 policy identity mismatch" }
if ($dryPair -ne $ExpectedDryPair -or $wetPair -ne $ExpectedWetPair) { throw "E2.5 paired evidence mismatch" }
if ($runA -notmatch '(?m)^dry_classification=ADAPTATION_DETECTED$' -or $runA -notmatch '(?m)^wet_classification=ADAPTATION_DETECTED$') { throw "E2.5 causal classification mismatch" }
$dryGain = Parse-Number $runA "dry_adaptation_gain"
$wetGain = Parse-Number $runA "wet_adaptation_gain"
$dryHome = Parse-Number $runA "cross_dry_home"
$dryAway = Parse-Number $runA "cross_dry_away"
$wetHome = Parse-Number $runA "cross_wet_home"
$wetAway = Parse-Number $runA "cross_wet_away"
if ($dryGain -le 0.0 -or $wetGain -le 0.0) { throw "E2.5 measurable adaptation advantage missing" }
if ($dryHome -le $dryAway -or $wetHome -le $wetAway) { throw "E2.5 reciprocal home advantage missing" }

Write-Host "ECO.EVO2 E2.5 E2.4 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.5 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.5 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.5 reciprocal adaptation contrast: PASS"
Write-Host "ECO.EVO2 E2.5 aggregate_hash=$aggregate"
Write-Host "ECO.EVO2 E2.5 candidate automated gates: PASS"
