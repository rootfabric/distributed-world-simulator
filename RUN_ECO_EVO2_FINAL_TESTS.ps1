param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedE28Aggregate = "4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061"
$ExpectedE28Head = "5790de059aaafbfc10434bb2d40124e3c1ceb361"
$ExpectedTransport = "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1"
$ExpectedContent = "3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e"
$ExpectedProvenance = "a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15"
$ExpectedCatalog = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$ExpectedProtocolFreezeCommit = "d936efac36d2664ec2f24f26306fa3ba95409117"
$ExpectedProtocol = "d3dc2b0c2a251cf645d03430eb14ad2215166a5be03f5ec13b8eafb4d56678e1"
$ExpectedEvidence = "989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1"
$ExpectedArtifactBytes = 10383
$WriterScript = "res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_writer.gd"
$TestScript = "res://tests/research/ecology/eco_evo2_final_unseen_world_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical EVO2 FINAL runner requires a clean checkout" }

& git -C $RootDir merge-base --is-ancestor $ExpectedProtocolFreezeCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "FINAL_PROTOCOL_PRECOMMIT_NOT_ANCESTOR" }
$protocolDrift = (& git -C $RootDir diff --name-only "$ExpectedProtocolFreezeCommit..HEAD" -- "scripts/research/ecology/plant_evo2_unseen_world_protocol_v1.gd")
if ($LASTEXITCODE -ne 0 -or $protocolDrift) { throw "FINAL_PROTOCOL_DRIFT_AFTER_PRECOMMIT" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne "4.7.1.stable.double.custom_build.a13da4feb") { throw "GODOT_IDENTITY_MISMATCH: $version" }

$E28Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-8-catalog-persistence-validation.json"
$e28 = Get-Content -LiteralPath $E28Path -Raw | ConvertFrom-Json
if (-not ([string]$e28.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.8 parent is not ACCEPTED" }
if ([string]$e28.acceptance.aggregate_hash -ne $ExpectedE28Aggregate) { throw "E2.8 aggregate mismatch" }
if ([string]$e28.acceptance.code_under_test_head -ne $ExpectedE28Head) { throw "E2.8 head mismatch" }
if ([string]$e28.acceptance.transport_sha256 -ne $ExpectedTransport) { throw "E2.8 transport mismatch" }
if ([string]$e28.acceptance.content_hash -ne $ExpectedContent) { throw "E2.8 content mismatch" }
if ([string]$e28.acceptance.provenance_hash -ne $ExpectedProvenance) { throw "E2.8 provenance mismatch" }
if ([string]$e28.acceptance.catalog_hash -ne $ExpectedCatalog) { throw "E2.8 catalog mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_recruitment_traits_v1.gd" = "6faeff9da9f7fa5a03e1df586de9cb29795d30de"
    "scripts/research/ecology/plant_resource_model_v1.gd" = "26fd4118307f098bd85b6d4b953a27ad8b9d85cd"
    "scripts/research/ecology/plant_lineage_record_v1.gd" = "0b848b2dc3ed3dccc1ee02db71c161cfcc9809d0"
    "scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd" = "7b9b5d41236cb27256dd7405201436a71a3eafea"
    "scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd" = "151937ac24818dc792c6ac0abf298507e80c231d"
    "scripts/research/ecology/plant_establishment_seed_bank_v1.gd" = "493566ee8ccbc6c0fac63310f0e6d6b9e3bb982d"
    "scripts/research/ecology/plant_patch_migration_v1.gd" = "58dc4c5cecd4a1fd41740c79010bb357395c6807"
    "scripts/research/ecology/plant_accepted_e2_2_catalog_v1.gd" = "b77c3421325fa1264f590b0bd75c1c59621f667f"
    "scripts/research/ecology/plant_evo2_provenance_v1.gd" = "5602607fa3b63e79da28d8da52cb3ba5f61960c1"
    "scripts/research/ecology/plant_catalog_persistence_v1.gd" = "83f80afe9fd467f7718f487b70f6bf1a88521339"
    "scripts/research/ecology/plant_evo2_unseen_world_protocol_v1.gd" = "372591ee3bee1c19538729259373e97fd9838461"
    "scripts/research/ecology/plant_evo2_unseen_world_challenge_v1.gd" = "4d353e774887c45f8a0487cb17b782e44d563951"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_tamper_support.gd" = "227c57ff4f25c80dc3fa35e99f0e4fe791620eb7"
    "tests/research/ecology/eco_evo2_final_unseen_world_acceptance.gd" = "82850fb850c35bcffb937707e4a8d29fb2827caa"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_writer.gd" = "32f85fc1809af8c094227ecc702dbbc8e7e94608"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "FINAL execution file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "FINAL exact execution-set mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 FINAL exact GDScript execution set: PASS (17/17)"

$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
if ($LASTEXITCODE -ne 0 -or (($check -join "`n") -match '(?m)^ERROR:')) { throw "FINAL parser/preload failed" }

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("eco-evo2-final-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $artifactA = Join-Path $tempDir "artifact-a.bin"
    $artifactB = Join-Path $tempDir "artifact-b.bin"
    function Invoke-Writer([string]$Path, [string]$Label) {
        $output = & $GodotPath --headless --path $RootDir --script $WriterScript -- ("--artifact-path=" + $Path) 2>&1
        $joined = $output -join "`n"
        if ($LASTEXITCODE -ne 0 -or $joined -match '(?m)^ERROR:') { throw "$Label failed" }
        return $joined
    }
    $writerA = Invoke-Writer $artifactA "FINAL E2.8 writer A"
    $writerB = Invoke-Writer $artifactB "FINAL E2.8 writer B"
    $bytesA = [System.IO.File]::ReadAllBytes($artifactA)
    $bytesB = [System.IO.File]::ReadAllBytes($artifactB)
    if ($bytesA.Length -ne $ExpectedArtifactBytes -or $bytesB.Length -ne $ExpectedArtifactBytes) { throw "FINAL E2.8 artifact length mismatch" }
    if (-not [System.Linq.Enumerable]::SequenceEqual($bytesA, $bytesB)) { throw "FINAL E2.8 writer artifacts differ" }
    $shaA = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytesA))).Replace("-", "").ToLowerInvariant()
    if ($shaA -ne $ExpectedTransport) { throw "FINAL E2.8 writer artifact SHA mismatch" }

    function Invoke-Final([string]$ArtifactPath, [string]$Label) {
        $output = & $GodotPath --headless --path $RootDir --script $TestScript -- $ArtifactPath 2>&1
        $joined = $output -join "`n"
        if ($LASTEXITCODE -ne 0 -or $joined -match '(?m)^ERROR:') { throw "$Label failed" }
        if ($joined -notmatch 'ECO\.EVO2 FINAL Unseen World Challenge: PASS \(68 assertions\)') { throw "$Label missing PASS marker" }
        return $joined
    }
    $runA = Invoke-Final $artifactA "EVO2 FINAL A"
    $runB = Invoke-Final $artifactB "EVO2 FINAL fresh process B"
    if ($runA -ne $runB) { throw "FINAL fresh-process logs are not byte-identical" }

    function Parse-Hash([string]$Text, [string]$Name) {
        $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
        if (-not $m.Success) { throw "Unable to parse FINAL $Name" }
        return $m.Groups[1].Value
    }
    function Parse-Int([string]$Text, [string]$Name) {
        $m = [regex]::Match($Text, "(?m)^$Name=([0-9]+)$")
        if (-not $m.Success) { throw "Unable to parse FINAL $Name" }
        return [int]$m.Groups[1].Value
    }
    function Parse-Bool([string]$Text, [string]$Name) {
        $m = [regex]::Match($Text, "(?m)^$Name=(true|false)$")
        if (-not $m.Success) { throw "Unable to parse FINAL $Name" }
        return $m.Groups[1].Value -eq "true"
    }
    if ((Parse-Hash $runA "evidence_hash") -ne $ExpectedEvidence) { throw "FINAL evidence hash mismatch" }
    if ((Parse-Hash $runA "protocol_hash") -ne $ExpectedProtocol) { throw "FINAL protocol hash mismatch" }
    if ((Parse-Hash $runA "transport_sha256") -ne $ExpectedTransport) { throw "FINAL transport hash mismatch" }
    if ((Parse-Hash $runA "catalog_hash") -ne $ExpectedCatalog) { throw "FINAL catalog hash mismatch" }
    if ((Parse-Int $runA "reachable_colonized_patches") -lt 2) { throw "FINAL reachable colonization gate failed" }
    if ((Parse-Int $runA "unique_recruited_species") -lt 2) { throw "FINAL recruited species gate failed" }
    if (-not (Parse-Bool $runA "isolated_no_colonization")) { throw "FINAL isolated control gate failed" }
    if ((Parse-Int $runA "sorting_observed_cells") -lt 1) { throw "FINAL sorting gate failed" }
    if ((Parse-Int $runA "adaptation_positive_cells") -lt 1) { throw "FINAL adaptation gate failed" }

    Write-Host "ECO.EVO2 FINAL E2.8 fresh writer: PASS"
    Write-Host "ECO.EVO2 FINAL protocol precommit gate: PASS"
    Write-Host "ECO.EVO2 FINAL parser/preload: PASS"
    Write-Host "ECO.EVO2 FINAL fresh-process determinism: PASS"
    Write-Host "ECO.EVO2 FINAL evidence_hash=$ExpectedEvidence"
    Write-Host "ECO.EVO2 FINAL candidate automated gates: PASS"
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
