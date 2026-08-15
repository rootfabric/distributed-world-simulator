$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"

$ExpectedValidationBlobs = [ordered]@{
    "validation/ecology/eco-p4-1-production-region-state-validation.json" = "9a18978a4206452d58d32eb3ec49e2effdff26f6"
    "validation/ecology/eco-p4-2-deterministic-clock-validation.json" = "730452dc2bcd8fe58e758197e0209e6bc38b540c"
    "validation/ecology/eco-p4-3-offline-catchup-validation.json" = "1236fdefcf490838bbe69431588d5878b7949f2c"
    "validation/ecology/eco-p4-4-production-persistence-validation.json" = "9f540c402506b1494d8ac69ca6a81a76696bab2f"
    "validation/ecology/eco-p4-5-region-ownership-validation.json" = "a02f1547c1beea5a49d500304b58ab8c763334ca"
    "validation/ecology/eco-p4-6-client-read-model-validation.json" = "d2bcd0342c882ef9c2c161ddef949c2ea0d0e8fc"
}

$ExpectedP47ValidationBlob = "747d1406971bc69bd81b6d149481da00d65d5a47"
$ExpectedP47RunnerBlob = "2bd6e1da8951238ff36b61e9ca5813a125e0dcd4"
$ExpectedP47TestBlob = "49821079787479212feb78a10a4703bc52ba89b3"
$ExpectedP47Status = "ACCEPTED_EXACT_WINDOWS_ISOLATED_HEADLESS_BOUNDED_ROTATING_A_B"
$ExpectedP47TestedHead = "cb5f6c69bfb0299770e09d3acff41a8fbf8aa61c"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedSoakHash = "d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe"
$ExpectedInterestHash = "62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}

foreach ($entry in $ExpectedValidationBlobs.GetEnumerator()) {
    Assert-Blob $entry.Key $entry.Value
    $validation = Get-Content -LiteralPath (Join-Path $RootDir $entry.Key) -Raw | ConvertFrom-Json
    if (-not ([string]$validation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
        throw "P4.8 final gate requires accepted ancestor: path=$($entry.Key) status=$($validation.status)"
    }
}

Assert-Blob "validation/ecology/eco-p4-7-production-integration-soak-validation.json" $ExpectedP47ValidationBlob
Assert-Blob "RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1" $ExpectedP47RunnerBlob
Assert-Blob "tests/ecology/production/eco_p4_7_production_integration_soak.gd" $ExpectedP47TestBlob

$p47 = Get-Content -LiteralPath (Join-Path $RootDir "validation/ecology/eco-p4-7-production-integration-soak-validation.json") -Raw | ConvertFrom-Json
if ([string]$p47.status -ne $ExpectedP47Status) { throw "P4.7 acceptance status mismatch" }
if ([string]$p47.accepted_candidate.tested_head -ne $ExpectedP47TestedHead) { throw "P4.7 tested head mismatch" }
if ([string]$p47.accepted_candidate.godot -ne $ExpectedGodot) { throw "P4.7 Godot identity mismatch" }
if ([string]$p47.acceptance_evidence.frozen_soak_hash -ne $ExpectedSoakHash) { throw "P4.7 frozen soak hash mismatch" }
if ([string]$p47.acceptance_evidence.frozen_final_interest_hash -ne $ExpectedInterestHash) { throw "P4.7 frozen interest hash mismatch" }
if (-not [bool]$p47.acceptance_evidence.fresh_process_logs_byte_identical) { throw "P4.7 A/B logs were not recorded byte-identical" }
if ([string]$p47.acceptance_evidence.canonical_automated_gates -ne "PASS") { throw "P4.7 canonical gate evidence missing" }

$counts = $p47.acceptance_evidence.counts
if ([int]$counts.regions -ne 8) { throw "P4.7 regions mismatch" }
if ([int]$counts.cycles -ne 12) { throw "P4.7 cycles mismatch" }
if ([int]$counts.ecology_generation_steps -ne 8) { throw "P4.7 ecology generation count mismatch" }
if ([int]$counts.handoffs -ne 4) { throw "P4.7 handoff count mismatch" }
if ([int]$counts.save_loads -ne 12) { throw "P4.7 save/load count mismatch" }
if ([int]$counts.client_updates -ne 12) { throw "P4.7 client update count mismatch" }
if ([int]$counts.interest_projections -ne 14) { throw "P4.7 interest projection count mismatch" }
if ([int]$counts.restarts -ne 3) { throw "P4.7 restart count mismatch" }
if ([int]$counts.max_remaining_due_steps -ne 0) { throw "P4.7 debt evidence mismatch" }

Write-Host "ECO.P4.8 accepted ancestors P4.1-P4.6: PASS"
Write-Host "ECO.P4.8 accepted P4.7 exact identities: PASS"
Write-Host "ECO.P4.8 P4.7 frozen soak_hash=$ExpectedSoakHash"
Write-Host "ECO.P4.8 P4.7 frozen final_interest_hash=$ExpectedInterestHash"
Write-Host "ECO.P4.8 final manifest gate: PASS"
Write-Host "ECO.P4.8 FINAL GATES: PASS"
