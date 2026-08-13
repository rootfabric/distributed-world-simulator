param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP41 = "1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717"
$ExpectedP41KernelBlob = "b651d208abd17050367fed4541c92f58de0f3c3f"
$ExpectedKernelBlob = "e6a1336059fdfa16143df0957206cc78b0f86bff"
$ExpectedTestBlob = "2ac25dbdd2644b72ddbfe14db3c35434bfaac7c7"
$ExpectedAggregate = "607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e"
$ExpectedClock = "f62815a7be67d7db2aeaa809915924ba2eb0437521ef6c908239642ba6909899"
$ExpectedGeneration5 = "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
$ExpectedDecimal100 = "6b291c025ec6f2eb5904741b1c09959942f1bd10ef10a5e5b14886bf63a62692"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "GODOT_IDENTITY_MISMATCH: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p4-1-production-region-state-validation.json"
if (-not (Test-Path -LiteralPath $parentValidationPath -PathType Leaf)) { throw "P4.1 validation missing" }
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
if (-not ([string]$parentValidation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) {
    throw "P4.1 parent is not ACCEPTED: status=$($parentValidation.status)"
}

function Assert-Blob([string]$Path, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object $Path).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to hash $Path" }
    if ($actual -ne $Expected) { throw "BLOB_MISMATCH: path=$Path expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/ecology/production/ecology_region_state_v1.gd" $ExpectedP41KernelBlob
Assert-Blob "scripts/ecology/production/ecology_clock_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_2_deterministic_clock_acceptance.gd" $ExpectedTestBlob

Write-Host "=== ECO P4.2 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/ecology/production/eco_p4_2_deterministic_clock_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P4.2 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P4.2 parser/preload emitted Godot ERROR output" }

Write-Host "=== ECO P4.1 accepted parent regression ==="
& (Join-Path $RootDir "RUN_ECO_P4_1_TESTS.ps1") -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "P4.1 accepted parent regression failed" }

function Invoke-P42([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script res://tests/ecology/production/eco_p4_2_deterministic_clock_acceptance.gd 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

$runA = Invoke-P42 "ECO P4.2 deterministic clock A"
$runB = Invoke-P42 "ECO P4.2 deterministic clock fresh process B"
if ($runA -ne $runB) { throw "P4.2 fresh-process logs are not byte-identical" }

$aggregate = [regex]::Match($runA, 'aggregate_hash=([0-9a-f]{64})')
$clock = [regex]::Match($runA, 'clock_hash=([0-9a-f]{64})')
$generation5 = [regex]::Match($runA, 'generation_5_region_hash=([0-9a-f]{64})')
$decimal100 = [regex]::Match($runA, 'decimal_generation_100_region_hash=([0-9a-f]{64})')
$parent = [regex]::Match($runA, 'parent_p4_1=([0-9a-f]{64})')
foreach ($match in @($aggregate,$clock,$generation5,$decimal100,$parent)) {
    if (-not $match.Success) { throw "Unable to parse P4.2 canonical output" }
}
if ($aggregate.Groups[1].Value -ne $ExpectedAggregate) { throw "P4.2 aggregate mismatch" }
if ($clock.Groups[1].Value -ne $ExpectedClock) { throw "P4.2 clock hash mismatch" }
if ($generation5.Groups[1].Value -ne $ExpectedGeneration5) { throw "P4.2 generation-five region mismatch" }
if ($decimal100.Groups[1].Value -ne $ExpectedDecimal100) { throw "P4.2 decimal generation-100 mismatch" }
if ($parent.Groups[1].Value -ne $ExpectedParentP41) { throw "P4.2 P4.1 parent mismatch" }

Write-Host "ECO.P4.1 accepted parent regression: PASS"
Write-Host "ECO.P4.2 deterministic ecology clock fresh-process determinism: PASS"
Write-Host "ECO.P4.2 aggregate_hash=$($aggregate.Groups[1].Value)"
Write-Host "ECO.P4.2 clock_hash=$($clock.Groups[1].Value)"
Write-Host "ECO.P4.2 generation_5_region_hash=$($generation5.Groups[1].Value)"
Write-Host "ECO.P4.2 decimal_generation_100_region_hash=$($decimal100.Groups[1].Value)"
Write-Host "ECO.P4.2 parent_p4_1=$($parent.Groups[1].Value)"
Write-Host "ECO.P4.2 candidate automated gates: PASS"
