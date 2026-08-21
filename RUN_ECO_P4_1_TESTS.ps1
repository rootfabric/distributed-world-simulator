param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedParentP38 = "6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0"
$ExpectedP38KernelBlob = "3d752f0d0a91fbbca5303b8ac7d49a8d8065c14e"
$ExpectedKernelBlob = "b651d208abd17050367fed4541c92f58de0f3c3f"
$ExpectedTestBlob = "f1d607a08c2c3f35f5a582557adcd3e2b9a60ab3"
$ExpectedAggregate = "1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717"
$ExpectedRegionZero = "2d7fc8f595dbe5e55e29a0dca1256a9f4ccebe4176ec8d53c9bf66671ac3b7b4"
$ExpectedRegionCut = "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
$ExpectedOtherRegion = "d4f0cd4890678747ef2f2399bcfd500282a3840af43ea37913ee78c39b17c3e5"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$version = (& $GodotPath --version 2>&1 | Select-Object -First 1).Trim()
if ($version -ne $ExpectedGodot) { throw "WRONG_GODOT: expected=$ExpectedGodot actual=$version" }

$parentValidationPath = Join-Path $RootDir "validation/ecology/eco-p3-8-deterministic-ecosystem-persistence-validation.json"
$parentValidation = Get-Content -LiteralPath $parentValidationPath -Raw | ConvertFrom-Json
$parentStatus = [string]$parentValidation.status
if (-not $parentStatus.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "P3.8 parent is not ACCEPTED: status=$parentStatus" }
if (-not (Get-Content -LiteralPath $parentValidationPath -Raw).Contains($ExpectedParentP38)) { throw "P3.8 accepted aggregate pin not found" }

function Assert-Blob([string]$RelativePath, [string]$Expected) {
    $actual = (& git -C $RootDir hash-object -- $RelativePath).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $Expected) { throw "BLOB_MISMATCH: $RelativePath expected=$Expected actual=$actual" }
}
Assert-Blob "scripts/research/ecology/plant_ecosystem_persistence_v1.gd" $ExpectedP38KernelBlob
Assert-Blob "scripts/ecology/production/ecology_region_state_v1.gd" $ExpectedKernelBlob
Assert-Blob "tests/ecology/production/eco_p4_1_region_state_acceptance.gd" $ExpectedTestBlob

function Invoke-Godot([string]$Label) {
    Write-Host "=== $Label ==="
    $previousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $output = & $GodotPath --headless --path $RootDir --script res://tests/ecology/production/eco_p4_1_region_state_acceptance.gd 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousBreakpoint) { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $previousBreakpoint }
    }
    $output | ForEach-Object { Write-Host $_ }
    $joined = ($output -join "`n")
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output despite zero exit code" }
    return $joined
}

Write-Host "=== ECO P4.1 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script res://tests/ecology/production/eco_p4_1_region_state_acceptance.gd 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "P4.1 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "P4.1 parser/preload preflight emitted Godot ERROR output" }

$runA = Invoke-Godot "ECO P4.1 production ecology region contract A"
$runB = Invoke-Godot "ECO P4.1 production ecology region contract fresh process B"
if ($runA -ne $runB) { throw "P4.1 fresh-process logs are not byte-identical" }
function Parse-Hash([string]$Output, [string]$Name) {
    $m = [regex]::Match($Output, [regex]::Escape($Name) + '=([0-9a-f]{64})')
    if (-not $m.Success) { throw "Unable to parse P4.1 $Name" }
    return $m.Groups[1].Value
}
$aggregate = Parse-Hash $runA "aggregate_hash"
$regionZero = Parse-Hash $runA "region_zero_hash"
$regionCut = Parse-Hash $runA "region_cut_hash"
$otherRegion = Parse-Hash $runA "other_region_hash"
$parent = Parse-Hash $runA "parent_p3_8"
if ($aggregate -ne $ExpectedAggregate) { throw "P4.1 aggregate mismatch: expected=$ExpectedAggregate actual=$aggregate" }
if ($regionZero -ne $ExpectedRegionZero) { throw "P4.1 region-zero mismatch" }
if ($regionCut -ne $ExpectedRegionCut) { throw "P4.1 region-cut mismatch" }
if ($otherRegion -ne $ExpectedOtherRegion) { throw "P4.1 other-region mismatch" }
if ($parent -ne $ExpectedParentP38) { throw "P4.1 P3.8 parent mismatch" }
Write-Host "ECO.P4.1 accepted P3.8 parent boundary: PASS"
Write-Host "ECO.P4.1 fresh-process determinism: PASS"
Write-Host "ECO.P4.1 aggregate_hash=$aggregate"
Write-Host "ECO.P4.1 parent_p3_8=$parent"
Write-Host "ECO.P4.1 candidate automated gates: PASS"
