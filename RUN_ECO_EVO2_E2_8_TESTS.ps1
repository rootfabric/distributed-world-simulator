param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE27Aggregate = "eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d"
$ExpectedParentE27Head = "52f31ca58a77296d63b1642954659edcbd12b8fe"
$ExpectedParentE27SeedEnsemble = "a49ce9d6856e08e1e0a61f060a8019de61685cdc63b25229b3761c9e7c9d792f"
$ExpectedAggregate = "4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061"
$ExpectedContentHash = "3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e"
$ExpectedProvenanceHash = "a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15"
$ExpectedTransportSha256 = "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1"
$ExpectedCatalogHash = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$ExpectedBakeId = "eco-evo2-bake/ff406486cc83bb8217d66213"
$ExpectedArtifactBytes = 10383
$TestScript = "res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_acceptance.gd"
$WriterScript = "res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_writer.gd"
$RestoreScript = "res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_restore.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }
$dirty = (& git -C $RootDir status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect worktree" }
if ($dirty) { throw "DIRTY_WORKTREE: canonical E2.8 runner requires a clean checkout" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne "4.7.1.stable.double.custom_build.a13da4feb") { throw "GODOT_IDENTITY_MISMATCH: $version" }

$E27Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-7-cross-seed-robustness-validation.json"
if (-not (Test-Path -LiteralPath $E27Path -PathType Leaf)) { throw "E2.7 validation file not found: $E27Path" }
$e27 = Get-Content -LiteralPath $E27Path -Raw | ConvertFrom-Json
if (-not ([string]$e27.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.7 parent is not ACCEPTED" }
if ([string]$e27.acceptance.aggregate_hash -ne $ExpectedParentE27Aggregate) { throw "E2.7 accepted aggregate mismatch" }
if ([string]$e27.acceptance.code_under_test_head -ne $ExpectedParentE27Head) { throw "E2.7 accepted code-under-test mismatch" }
if ([string]$e27.acceptance.seed_ensemble_hash -ne $ExpectedParentE27SeedEnsemble) { throw "E2.7 seed-ensemble mismatch" }

$ExpectedBlobs = [ordered]@{
    "scripts/research/ecology/environment_sample_v1.gd" = "7ae8cc2534940ceb3c69879f8850467ba32fea8c"
    "scripts/research/ecology/plant_genome_v1.gd" = "6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd"
    "scripts/research/ecology/plant_recruitment_traits_v1.gd" = "6faeff9da9f7fa5a03e1df586de9cb29795d30de"
    "scripts/research/ecology/plant_accepted_e2_2_catalog_v1.gd" = "b77c3421325fa1264f590b0bd75c1c59621f667f"
    "scripts/research/ecology/plant_evo2_provenance_v1.gd" = "5602607fa3b63e79da28d8da52cb3ba5f61960c1"
    "scripts/research/ecology/plant_catalog_persistence_v1.gd" = "83f80afe9fd467f7718f487b70f6bf1a88521339"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_tamper_support.gd" = "227c57ff4f25c80dc3fa35e99f0e4fe791620eb7"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_acceptance.gd" = "8e0f0d2ba6eea03337f6559276da87cf5f689d4b"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_writer.gd" = "32f85fc1809af8c094227ecc702dbbc8e7e94608"
    "tests/research/ecology/eco_evo2_e2_8_catalog_persistence_restore.gd" = "5d7c698a8e30a6be9622ddd9c5c08f02feac351e"
}
foreach ($entry in $ExpectedBlobs.GetEnumerator()) {
    $path = Join-Path $RootDir $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "E2.8 closure file missing: $($entry.Key)" }
    $actual = (& git -C $RootDir hash-object -- $entry.Key).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $entry.Value) { throw "E2.8 exact closure mismatch: $($entry.Key) expected $($entry.Value) actual $actual" }
}
Write-Host "ECO.EVO2 E2.8 exact transitive executable closure: PASS (10/10)"

$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.8 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.8 parser/preload emitted Godot ERROR output" }

function Invoke-E28Acceptance([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.8 Catalog Persistence & Provenance: PASS \(74 assertions\)') { throw "$Label did not emit E2.8 PASS marker" }
    return $joined
}
function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.8 $Name" }
    return $m.Groups[1].Value
}
function Parse-Text([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([^\r\n]+)$")
    if (-not $m.Success) { throw "Unable to parse E2.8 $Name" }
    return $m.Groups[1].Value
}
function Parse-Int([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9]+)$")
    if (-not $m.Success) { throw "Unable to parse E2.8 $Name" }
    return [int]$m.Groups[1].Value
}

$runA = Invoke-E28Acceptance "ECO EVO2 E2.8 acceptance A"
$runB = Invoke-E28Acceptance "ECO EVO2 E2.8 acceptance fresh process B"
if ($runA -ne $runB) { throw "E2.8 fresh acceptance logs are not byte-identical" }
if ((Parse-Hash $runA "aggregate_hash") -ne $ExpectedAggregate) { throw "E2.8 aggregate mismatch" }
if ((Parse-Hash $runA "content_hash") -ne $ExpectedContentHash) { throw "E2.8 content hash mismatch" }
if ((Parse-Hash $runA "provenance_hash") -ne $ExpectedProvenanceHash) { throw "E2.8 provenance hash mismatch" }
if ((Parse-Hash $runA "transport_sha256") -ne $ExpectedTransportSha256) { throw "E2.8 transport hash mismatch" }
if ((Parse-Hash $runA "catalog_hash") -ne $ExpectedCatalogHash) { throw "E2.8 catalog hash mismatch" }
if ((Parse-Text $runA "bake_id") -ne $ExpectedBakeId) { throw "E2.8 bake id mismatch" }
if ((Parse-Int $runA "artifact_bytes") -ne $ExpectedArtifactBytes) { throw "E2.8 artifact byte size mismatch" }
if ((Parse-Hash $runA "parent_e2_7") -ne $ExpectedParentE27Aggregate) { throw "E2.8 parent E2.7 mismatch" }

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-e28-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $artifactA = Join-Path $tempDir "catalog-a.e28"
    $artifactB = Join-Path $tempDir "catalog-b.e28"
    function Invoke-E28Writer([string]$Label, [string]$ArtifactPath) {
        $output = & $GodotPath --headless --path $RootDir --script $WriterScript -- "--artifact-path=$ArtifactPath" 2>&1
        $exitCode = $LASTEXITCODE
        $joined = $output -join "`n"
        if ($exitCode -ne 0 -or $joined -match '(?m)^ERROR:' -or $joined -notmatch 'ECO\.EVO2 E2\.8 writer: PASS') { throw "$Label failed" }
        return $joined
    }
    function Invoke-E28Restore([string]$Label, [string]$ArtifactPath) {
        $output = & $GodotPath --headless --path $RootDir --script $RestoreScript -- "--artifact-path=$ArtifactPath" 2>&1
        $exitCode = $LASTEXITCODE
        $joined = $output -join "`n"
        if ($exitCode -ne 0 -or $joined -match '(?m)^ERROR:' -or $joined -notmatch 'ECO\.EVO2 E2\.8 restore: PASS') { throw "$Label failed" }
        return $joined
    }
    $writerA = Invoke-E28Writer "E2.8 writer A" $artifactA
    $writerB = Invoke-E28Writer "E2.8 writer B" $artifactB
    if ($writerA -ne $writerB) { throw "E2.8 writer logs differ across fresh processes" }
    $shaA = (Get-FileHash -LiteralPath $artifactA -Algorithm SHA256).Hash.ToLowerInvariant()
    $shaB = (Get-FileHash -LiteralPath $artifactB -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($shaA -ne $ExpectedTransportSha256 -or $shaB -ne $ExpectedTransportSha256) { throw "E2.8 writer artifact SHA mismatch" }
    if ((Get-Item -LiteralPath $artifactA).Length -ne $ExpectedArtifactBytes -or (Get-Item -LiteralPath $artifactB).Length -ne $ExpectedArtifactBytes) { throw "E2.8 writer artifact size mismatch" }
    $bytesA = [System.IO.File]::ReadAllBytes($artifactA)
    $bytesB = [System.IO.File]::ReadAllBytes($artifactB)
    if (-not [System.Linq.Enumerable]::SequenceEqual($bytesA, $bytesB)) { throw "E2.8 fresh writers did not produce byte-identical artifacts" }
    $restoreA = Invoke-E28Restore "E2.8 restore A" $artifactA
    $restoreB = Invoke-E28Restore "E2.8 restore B" $artifactB
    if ($restoreA -ne $restoreB) { throw "E2.8 restore logs differ across fresh processes" }
    foreach ($restore in @($restoreA, $restoreB)) {
        if ((Parse-Hash $restore "content_hash") -ne $ExpectedContentHash) { throw "E2.8 restored content hash mismatch" }
        if ((Parse-Hash $restore "provenance_hash") -ne $ExpectedProvenanceHash) { throw "E2.8 restored provenance hash mismatch" }
        if ((Parse-Hash $restore "transport_sha256") -ne $ExpectedTransportSha256) { throw "E2.8 restored transport hash mismatch" }
        if ((Parse-Hash $restore "catalog_hash") -ne $ExpectedCatalogHash) { throw "E2.8 restored catalog hash mismatch" }
        if ((Parse-Int $restore "entry_count") -ne 2) { throw "E2.8 restored entry count mismatch" }
        if ((Parse-Hash $restore "parent_e2_7") -ne $ExpectedParentE27Aggregate) { throw "E2.8 restored parent mismatch" }
    }
}
finally {
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}

Write-Host "ECO.EVO2 E2.8 E2.7 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.8 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.8 semantic/tamper acceptance: PASS (74/74)"
Write-Host "ECO.EVO2 E2.8 fresh acceptance determinism: PASS"
Write-Host "ECO.EVO2 E2.8 fresh writer byte determinism: PASS"
Write-Host "ECO.EVO2 E2.8 fresh restore semantic identity: PASS"
Write-Host "ECO.EVO2 E2.8 aggregate_hash=$ExpectedAggregate"
Write-Host "ECO.EVO2 E2.8 candidate automated gates: PASS"
