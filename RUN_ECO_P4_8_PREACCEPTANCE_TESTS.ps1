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
$ExpectedP47ValidationBlob = "8d1f96f34cf5b4095323ac5d1a99d8053280a255"
$ExpectedP47RunnerBlob = "5d44dead6bf9bcb5f921e3baf4852acc54adff2c"
$ExpectedP47Status = "CANDIDATE_BOUNDED_ROTATING_CANONICAL_RUNNER_EXACT_COMMITTED_A_B_PENDING"

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
        throw "P4.8 preparation requires accepted ancestor: path=$($entry.Key) status=$($validation.status)"
    }
}

Assert-Blob "validation/ecology/eco-p4-7-production-integration-soak-validation.json" $ExpectedP47ValidationBlob
Assert-Blob "RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1" $ExpectedP47RunnerBlob
$p47 = Get-Content -LiteralPath (Join-Path $RootDir "validation/ecology/eco-p4-7-production-integration-soak-validation.json") -Raw | ConvertFrom-Json
if ([string]$p47.status -ne $ExpectedP47Status) {
    throw "P4.7 canonical gate state mismatch: expected=$ExpectedP47Status actual=$($p47.status)"
}

Write-Host "ECO.P4.8 acceptance preparation ancestors P4.1-P4.6: PASS"
Write-Host "ECO.P4.8 P4.7 bounded rotating observable canonical runner readiness: PASS"
Write-Host "ECO.P4.8 acceptance remains BLOCKED until P4.7 exact committed A/B soak accepts"
Write-Host "ECO.P4.8 PRE-ACCEPTANCE preparation gates: PASS"
