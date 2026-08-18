param([string]$GodotPath = $env:GODOT_BIN)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedParentE22 = "56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce"
$ExpectedBake = "45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b"
$ExpectedCatalog = "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
$TestScript = "res://tests/research/ecology/eco_evo2_e2_3_frozen_catalog_transfer_acceptance.gd"

$currentBranch = (& git -C $RootDir branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) { throw "Unable to determine current Git branch" }
if ($currentBranch -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected $ExpectedBranch actual $currentBranch" }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

$E22Path = Join-Path $RootDir "validation/ecology/eco-evo2-e2-2-evolution-bake-export-validation.json"
if (-not (Test-Path -LiteralPath $E22Path -PathType Leaf)) { throw "E2.2 validation file not found: $E22Path" }
$e22 = Get-Content -LiteralPath $E22Path -Raw | ConvertFrom-Json
if (-not ([string]$e22.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)) { throw "E2.2 parent is not ACCEPTED" }
if ([string]$e22.acceptance.aggregate_hash -ne $ExpectedParentE22) { throw "E2.2 accepted aggregate mismatch" }
if ([string]$e22.exact_attached_godot.bake_hash -ne $ExpectedBake) { throw "E2.2 accepted bake hash mismatch" }
if ([string]$e22.exact_attached_godot.catalog_hash -ne $ExpectedCatalog) { throw "E2.2 accepted catalog hash mismatch" }

Write-Host "=== ECO EVO2 E2.3 parser/preload preflight ==="
$check = & $GodotPath --headless --path $RootDir --check-only --script $TestScript 2>&1
$checkExit = $LASTEXITCODE
$check | ForEach-Object { Write-Host $_ }
if ($checkExit -ne 0) { throw "E2.3 parser/preload preflight failed" }
if (($check -join "`n") -match '(?m)^ERROR:') { throw "E2.3 parser/preload emitted Godot ERROR output" }

function Invoke-E23([string]$Label) {
    Write-Host "=== $Label ==="
    $output = & $GodotPath --headless --path $RootDir --script $TestScript 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    $joined = $output -join "`n"
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode" }
    if ($joined -match '(?m)^ERROR:') { throw "$Label emitted Godot ERROR output" }
    if ($joined -notmatch 'ECO\.EVO2 E2\.3 Frozen-Catalog Transfer: PASS \(59 assertions\)') { throw "$Label did not emit E2.3 PASS marker" }
    return $joined
}

$runA = Invoke-E23 "ECO EVO2 E2.3 frozen transfer A"
$runB = Invoke-E23 "ECO EVO2 E2.3 frozen transfer fresh process B"
if ($runA -ne $runB) { throw "E2.3 fresh-process logs are not byte-identical" }

function Parse-Hash([string]$Text, [string]$Name) {
    $m = [regex]::Match($Text, "(?m)^$Name=([0-9a-f]{64})$")
    if (-not $m.Success) { throw "Unable to parse E2.3 $Name" }
    return $m.Groups[1].Value
}
$aggregate = Parse-Hash $runA "aggregate_hash"
$parentE22 = Parse-Hash $runA "parent_e2_2"
$bake = Parse-Hash $runA "bake_hash"
$catalog = Parse-Hash $runA "catalog_hash"
$reachableTarget = Parse-Hash $runA "reachable_target_hash"
$reachableResult = Parse-Hash $runA "reachable_result_hash"
$reachableFinal = Parse-Hash $runA "reachable_final_state_hash"
$isolatedTarget = Parse-Hash $runA "isolated_target_hash"
$isolatedResult = Parse-Hash $runA "isolated_result_hash"
$isolatedFinal = Parse-Hash $runA "isolated_final_state_hash"
if ($parentE22 -ne $ExpectedParentE22) { throw "E2.3 E2.2 parent mismatch" }
if ($bake -ne $ExpectedBake) { throw "E2.3 frozen bake mismatch" }
if ($catalog -ne $ExpectedCatalog) { throw "E2.3 frozen catalog mismatch" }
if ($reachableResult -eq $isolatedResult) { throw "E2.3 reachable and isolated controls unexpectedly match" }
if ($runA -notmatch '(?m)^isolated_status=VALID_NO_COLONIZATION$') { throw "E2.3 no-colonization control marker missing" }

Write-Host "ECO.EVO2 E2.3 E2.2 accepted parent gate: PASS"
Write-Host "ECO.EVO2 E2.3 parser/preload: PASS"
Write-Host "ECO.EVO2 E2.3 fresh-process determinism: PASS"
Write-Host "ECO.EVO2 E2.3 aggregate_hash=$aggregate"
Write-Host "ECO.EVO2 E2.3 reachable_result_hash=$reachableResult"
Write-Host "ECO.EVO2 E2.3 isolated_result_hash=$isolatedResult"
Write-Host "ECO.EVO2 E2.3 candidate automated gates: PASS"
