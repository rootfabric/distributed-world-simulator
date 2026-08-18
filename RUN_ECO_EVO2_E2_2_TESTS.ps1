param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE21 = "aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad"
$ExpectedParentP28 = "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"
$ExpectedAggregate = "56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce"
$ExpectedSource = "c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9"
$ExpectedBake = "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
$ExpectedCatalog = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$TestScript = "res://tests/research/ecology/eco_evo2_e2_2_evolution_bake_export_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$E21Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-1-species-catalog-validation.json"
$P28Path = Join-Path $RootDir "validation/ecology/eco-evo1-p2-8-save-restart-validation.json"
foreach ($path in @($E21Path, $P28Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Parent validation not found: $path" }
}
$e21 = Get-Content -LiteralPath $E21Path -Raw | ConvertFrom-Json
$p28 = Get-Content -LiteralPath $P28Path -Raw | ConvertFrom-Json
if (-not ([string]$e21.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.1 parent is not ACCEPTED" }
if ([string]$e21.acceptance.aggregate_hash -ne $ExpectedParentE21) { throw "E2.1 accepted aggregate mismatch" }
if (-not ([string]$p28.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "P2.8 parent is not ACCEPTED" }
if ([string]$p28.canonical_acceptance.aggregate_hash -ne $ExpectedParentP28) { throw "P2.8 accepted aggregate mismatch" }

Write-Host "=== ECO EVO2 E2.2 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.2 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.2 parser/preload emitted Godot ERROR output" }

function Invoke-E22([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.2 Deterministic Evolution Bake Export: PASS \(60 assertions\)') { throw "$Label did not emit E2.2 PASS marker" }
    return $joined
}

$runA = Invoke-E22 "ECO EVO2 E2.2 bake export A"
$runB = Invoke-E22 "ECO EVO2 E2.2 bake export fresh process B"
if ($runA -ne $runB) { throw "E2.2 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.2 $Name" }
    return $m.Groups[1].Value
}
$aggregate = Parse-Hash $runA "aggregate_hash"
$source = Parse-Hash $runA "source_hash"
$bake = Parse-Hash $runA "bake_hash"
$catalog = Parse-Hash $runA "catalog_hash"
$parentE21 = Parse-Hash $runA "parent_e2_1"
$parentP28 = Parse-Hash $runA "parent_p2_8"
if ($aggregate -ne $ExpectedAggregate) { throw "E2.2 aggregate drift: expected=$ExpectedAggregate actual=$aggregate" }
if ($source -ne $ExpectedSource) { throw "E2.2 source hash drift" }
if ($bake -ne $ExpectedBake) { throw "E2.2 bake hash drift" }
if ($catalog -ne $ExpectedCatalog) { throw "E2.2 catalog hash drift" }
if ($parentE21 -ne $ExpectedParentE21) { throw "E2.2 E2.1 parent mismatch" }
if ($parentP28 -ne $ExpectedParentP28) { throw "E2.2 P2.8 parent mismatch" }

Write-Host "ECO.EVO2 E2.2 E2.1 parent gate: PASS"
Write-Host "ECO.EVO2 E2.2 P2.8 parent gate: PASS"
Write-Host "ECO.EVO2 E2.2 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.2 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.2 aggregate_hash=$aggregate"
Write-Host "ECO.EVO2 E2.2 source_hash=$source"
Write-Host "ECO.EVO2 E2.2 bake_hash=$bake"
Write-Host "ECO.EVO2 E2.2 catalog_hash=$catalog"
Write-Host "ECO.EVO2 E2.2 candidate automated gates: PASS"
