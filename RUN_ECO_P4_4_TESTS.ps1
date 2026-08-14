param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP43 = "4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62"
$ExpectedP43KernelBlob = "ed76af9537c09ca013eb1a1367d3c854b1438df3"
$ExpectedP43ValidationBlob = "1236fdefcf490838bbe69431588d5878b7949f2c"
$ExpectedKernelBlob = "2f4d7809a84d4f6d23a3f113c23b359f0803d564"
$ExpectedTestBlob = "2385b035082834aaae1eb91e25aa798c26ca40dc"
$ExpectedAggregate = "4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2"
$ExpectedSnapshot = "c6ee61dc4250fcd22b762902ff35354957c884c8b1818aed8209fe4f6c829006"
$ExpectedResumedCatchup = "cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-3-offline-catchup-validation.json"
if (-not (Test-Path -LiteralPath $parentValidationPath -PathType Leaf)) { throw "P4.3 validation missing" }
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$parentValidation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.3 parent is not ACCEPTED: status=$($parentValidation.status)"
}
if ([string]$parentValidation.acceptance_evidence.aggregate_hash -ne $ExpectedParentP43) {
    throw "P4.3 accepted aggregate mismatch"
}

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_offline_catchup_v1.gd" $ExpectedP43KernelBlob
Assert-Blob "validation/ecology/eco-p4-3-offline-catchup-validation.json" $ExpectedP43ValidationBlob
Assert-Blob "scripts/ecology/production/ecology_region_persistence_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_4_region_persistence_acceptance.gd" $ExpectedTestBlob

Write-Host "=== ECO P4.4 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/ecology/production/eco_p4_4_region_persistence_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P4.4 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P4.4 parser/preload emitted Godot ERROR output" }

Write-Host "=== ECO P4.3 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P4_3_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P4.3 accepted parent regression failed" }

function Invoke-P44([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script res://tests/ecology/production/eco_p4_4_region_persistence_acceptance.gd 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

$runA = Invoke-P44 "ECO P4.4 production persistence A"
$runB = Invoke-P44 "ECO P4.4 production persistence fresh process B"
if ($runA -ne $runB) { throw "P4.4 fresh-process logs are not byte-identical" }

$aggregate = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$snapshot = [regex]::Match($runA, 'snapshot_hash=([0-9a-f]{64})')
$fileSha = [regex]::Match($runA, 'file_sha256=([0-9a-f]{64})')
$resumed = [regex]::Match($runA, 'resumed_catchup_hash=([0-9a-f]{64})')
$parent = [regex]::Match($runA, 'parent_p4_3=([0-9a-f]{64})')
foreach ($match in @($aggregate,$snapshot,$fileSha,$resumed,$parent)) {
    if (-not $match.Success) { throw "Unable to parse P4.4 canonical output" }
}
if ($aggregate.Groups[1].Value -ne $ExpectedAggregate) { throw "P4.4 aggregate mismatch" }
if ($snapshot.Groups[1].Value -ne $ExpectedSnapshot) { throw "P4.4 snapshot hash mismatch" }
if ($resumed.Groups[1].Value -ne $ExpectedResumedCatchup) { throw "P4.4 resumed catch-up mismatch" }
if ($parent.Groups[1].Value -ne $ExpectedParentP43) { throw "P4.4 P4.3 parent mismatch" }

Write-Host "ECO.P4.3 accepted parent regression: PASS"
Write-Host "ECO.P4.4 production persistence fresh-process determinism: PASS"
Write-Host "ECO.P4.4 aggregate_hash=$($aggregate.Groups[1].Value)"
Write-Host "ECO.P4.4 snapshot_hash=$($snapshot.Groups[1].Value)"
Write-Host "ECO.P4.4 file_sha256=$($fileSha.Groups[1].Value)"
Write-Host "ECO.P4.4 resumed_catchup_hash=$($resumed.Groups[1].Value)"
Write-Host "ECO.P4.4 parent_p4_3=$($parent.Groups[1].Value)"
Write-Host "ECO.P4.4 candidate automated gates: PASS"
