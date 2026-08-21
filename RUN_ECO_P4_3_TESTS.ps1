param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP42 = "607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e"
$ExpectedP42KernelBlob = "e6a1336059fdfa16143df0957206cc78b0f86bff"
$ExpectedP42ValidationBlob = "730452dc2bcd8fe58e758197e0209e6bc38b540c"
$ExpectedKernelBlob = "ed76af9537c09ca013eb1a1367d3c854b1438df3"
$ExpectedTestBlob = "6aac302cff629a5e71b7ecd2f93f3973d437aa3f"
$ExpectedAggregate = "4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62"
$ExpectedCatchup = "cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a"
$ExpectedGeneration5 = "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-2-deterministic-clock-validation.json"
if (-not (Test-Path -LiteralPath $parentValidationPath -PathType Leaf)) { throw "P4.2 validation missing" }
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$parentValidation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.2 parent is not ACCEPTED: status=$($parentValidation.status)"
}
if ([string]$parentValidation.acceptance_evidence.aggregate_hash -ne $ExpectedParentP42) {
    throw "P4.2 accepted aggregate mismatch"
}

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_clock_v1.gd" $ExpectedP42KernelBlob
Assert-Blob "validation/ecology/eco-p4-2-deterministic-clock-validation.json" $ExpectedP42ValidationBlob
Assert-Blob "scripts/ecology/production/ecology_offline_catchup_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_3_offline_catchup_acceptance.gd" $ExpectedTestBlob

Write-Host "=== ECO P4.3 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/ecology/production/eco_p4_3_offline_catchup_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P4.3 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P4.3 parser/preload emitted Godot ERROR output" }

Write-Host "=== ECO P4.2 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P4_2_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P4.2 accepted parent regression failed" }

function Invoke-P43([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script res://tests/ecology/production/eco_p4_3_offline_catchup_acceptance.gd 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

$runA = Invoke-P43 "ECO P4.3 offline catch-up A"
$runB = Invoke-P43 "ECO P4.3 offline catch-up fresh process B"
if ($runA -ne $runB) { throw "P4.3 fresh-process logs are not byte-identical" }

$aggregate = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$catchup = [regex]::Match($runA, 'catchup_hash=([0-9a-f]{64})')
$generation5 = [regex]::Match($runA, 'generation_5_region_hash=([0-9a-f]{64})')
$parent = [regex]::Match($runA, 'parent_p4_2=([0-9a-f]{64})')
foreach ($match in @($aggregate,$catchup,$generation5,$parent)) {
    if (-not $match.Success) { throw "Unable to parse P4.3 canonical output" }
}
if ($aggregate.Groups[1].Value -ne $ExpectedAggregate) { throw "P4.3 aggregate mismatch" }
if ($catchup.Groups[1].Value -ne $ExpectedCatchup) { throw "P4.3 catch-up hash mismatch" }
if ($generation5.Groups[1].Value -ne $ExpectedGeneration5) { throw "P4.3 generation-five region mismatch" }
if ($parent.Groups[1].Value -ne $ExpectedParentP42) { throw "P4.3 P4.2 parent mismatch" }

Write-Host "ECO.P4.2 accepted parent regression: PASS"
Write-Host "ECO.P4.3 offline catch-up fresh-process determinism: PASS"
Write-Host "ECO.P4.3 aggregate_hash=$($aggregate.Groups[1].Value)"
Write-Host "ECO.P4.3 catchup_hash=$($catchup.Groups[1].Value)"
Write-Host "ECO.P4.3 generation_5_region_hash=$($generation5.Groups[1].Value)"
Write-Host "ECO.P4.3 parent_p4_2=$($parent.Groups[1].Value)"
Write-Host "ECO.P4.3 candidate automated gates: PASS"
