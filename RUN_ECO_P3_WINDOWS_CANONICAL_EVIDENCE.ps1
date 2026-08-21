param(
    [ValidateSet("Auto", "P31", "P32", "P33", "P34", "P35", "P36", "P37", "P38")]
    [string]$Stage = "Auto",
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"

$Aggregates = [ordered]@{
    P28 = "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"
    P31 = "f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a"
    P32 = "172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639"
    P33 = "37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41"
    P34 = "a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813"
    P35 = "255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83"
    P36 = "a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc"
    P37 = "ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a"
    P38 = "6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0"
}

$Stages = [ordered]@{
    P31 = [ordered]@{ label="P3.1"; validation="validation/ecology/eco-p3-1-resource-competition-validation.json"; runner="RUN_ECO_P3_1_TESTS.ps1"; parent="P28"; next="P32"; marker='ECO\.P3\.1 candidate automated gates: PASS'; aggregate='ECO\.P3\.1 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.1 parent_p2_8=([0-9a-f]{64})' }
    P32 = [ordered]@{ label="P3.2"; validation="validation/ecology/eco-p3-2-density-carrying-capacity-validation.json"; runner="RUN_ECO_P3_2_TESTS.ps1"; parent="P31"; next="P33"; marker='ECO\.P3\.2 candidate automated gates: PASS'; aggregate='ECO\.P3\.2 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.2 parent_p3_1=([0-9a-f]{64})' }
    P33 = [ordered]@{ label="P3.3"; validation="validation/ecology/eco-p3-3-spatial-dispersal-validation.json"; runner="RUN_ECO_P3_3_TESTS.ps1"; parent="P32"; next="P34"; marker='ECO\.P3\.3 candidate automated gates: PASS'; aggregate='ECO\.P3\.3 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.3 parent_p3_2=([0-9a-f]{64})' }
    P34 = [ordered]@{ label="P3.4"; validation="validation/ecology/eco-p3-4-environmental-gradient-validation.json"; runner="RUN_ECO_P3_4_TESTS.ps1"; parent="P33"; next="P35"; marker='ECO\.P3\.4 candidate automated gates: PASS'; aggregate='ECO\.P3\.4 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.4 parent_p3_3=([0-9a-f]{64})' }
    P35 = [ordered]@{ label="P3.5"; validation="validation/ecology/eco-p3-5-seasonal-world-validation.json"; runner="RUN_ECO_P3_5_TESTS.ps1"; parent="P34"; next="P36"; marker='ECO\.P3\.5 candidate automated gates: PASS'; aggregate='ECO\.P3\.5 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.5 parent_p3_4=([0-9a-f]{64})' }
    P36 = [ordered]@{ label="P3.6"; validation="validation/ecology/eco-p3-6-disturbance-succession-validation.json"; runner="RUN_ECO_P3_6_TESTS.ps1"; parent="P35"; next="P37"; marker='ECO\.P3\.6 candidate automated gates: PASS'; aggregate='ECO\.P3\.6 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.6 parent_p3_5=([0-9a-f]{64})' }
    P37 = [ordered]@{ label="P3.7"; validation="validation/ecology/eco-p3-7-multi-niche-coexistence-validation.json"; runner="RUN_ECO_P3_7_TESTS.ps1"; parent="P36"; next="P38"; marker='ECO\.P3\.7 candidate automated gates: PASS'; aggregate='ECO\.P3\.7 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.7 parent_p3_6=([0-9a-f]{64})' }
    P38 = [ordered]@{ label="P3.8"; validation="validation/ecology/eco-p3-8-deterministic-ecosystem-persistence-validation.json"; runner="RUN_ECO_P3_8_TESTS.ps1"; parent="P37"; next=""; marker='ECO\.P3\.8 candidate automated gates: PASS'; aggregate='ECO\.P3\.8 aggregate_hash=([0-9a-f]{64})'; parent_re='ECO\.P3\.8 parent_p3_7=([0-9a-f]{64})' }
}

$PinnedSurfaceBlobs = [ordered]@{
    "RUN_ECO_EVO1_P2_8_TESTS.ps1" = "2f263f562bbdde60e2cf2868c1bb30dd49ed4835"
    "RUN_ECO_P3_1_TESTS.ps1" = "3a4f1cf35f530da08485638cd907283cd9d6cc30"
    "scripts/research/ecology/plant_resource_competition_v1.gd" = "c667569b40775a1a1898d7b911a610ca5795f380"
    "tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd" = "421bf16651da64f92690ba2d676ecee7b3f97cf0"
    "RUN_ECO_P3_2_TESTS.ps1" = "9056e180bf806547b6ecd8ae9a75f8cc83fccdfc"
    "scripts/research/ecology/plant_density_carrying_capacity_v1.gd" = "8e635f8915ad53cac9a37917df32036cf92907b2"
    "tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd" = "c07e2c211ac9a5bf8ce58f323b3684b1e1e04028"
    "RUN_ECO_P3_3_TESTS.ps1" = "f6ebb17bc26b916711406c1808779f22dd20c496"
    "scripts/research/ecology/plant_spatial_dispersal_v1.gd" = "43a25eb0e6677749162de99c251231c94d243dc1"
    "tests/research/ecology/eco_p3_3_spatial_dispersal_acceptance.gd" = "9911c9197663098e1efa8875332b9d7c88ca34c6"
    "RUN_ECO_P3_4_TESTS.ps1" = "25f096ec918115f5b7d9447bfad0377dc93d2fd5"
    "scripts/research/ecology/plant_environmental_gradient_v1.gd" = "11e2b281c48d378da906f0739c739eecf9aa8465"
    "tests/research/ecology/eco_p3_4_environmental_gradient_acceptance.gd" = "f3412bd53ebe7d647b83266e4945d758924ab66b"
    "RUN_ECO_P3_5_TESTS.ps1" = "510ceaa8ed82902ea8a0b0c62f87fe038894b674"
    "scripts/research/ecology/plant_seasonal_world_v1.gd" = "649d26457ac8383f890f0dfca890353cc200ee7e"
    "tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd" = "c91ed0c25c418be1a7c7c4352423b7214c8706f8"
    "RUN_ECO_P3_6_TESTS.ps1" = "12b7da45290c52c420a7629ae2b6d0c3b0a558b6"
    "scripts/research/ecology/plant_disturbance_succession_v1.gd" = "ee83e97e3f4dbea23a591e745101aa3e2d235433"
    "tests/research/ecology/eco_p3_6_disturbance_succession_acceptance.gd" = "ef8e8565246fb454ed6483f95df3b33c1d253802"
    "RUN_ECO_P3_7_TESTS.ps1" = "51d326ad204a6c5bf6835784de6ec8de7a058265"
    "scripts/research/ecology/plant_multi_niche_coexistence_v1.gd" = "7379c422f2d3f5723a2bfff8b46790f9cce30ddc"
    "tests/research/ecology/eco_p3_7_multi_niche_coexistence_acceptance.gd" = "d14a24aaef42379ed199b9fbe3b4c3e9db58e15d"
    "RUN_ECO_P3_8_TESTS.ps1" = "51483ce2ae398a075a3aa829c6bd3b347d81752e"
    "scripts/research/ecology/plant_ecosystem_persistence_v1.gd" = "3d752f0d0a91fbbca5303b8ac7d49a8d8065c14e"
    "tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd" = "e0cef778f69ddd78b3f7d7aba6c3e2b8b9eef51c"
}

function Get-GitValue([string[]]$Arguments) {
    $value = (& git -C $RootDir @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $value" }
    return $value
}
function Read-Validation([string]$Path) {
    $absolute = Join-Path $RootDir $Path
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "VALIDATION_FILE_MISSING: $Path" }
    return Get-Content -LiteralPath $absolute -Raw | ConvertFrom-Json
}
function Accepted([object]$Validation) {
    return ([string]$Validation.status).StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)
}
function Match-One([string]$Text, [string]$Pattern, [string]$Label) {
    $m = [regex]::Match($Text, $Pattern)
    if (-not $m.Success) { throw "CANONICAL_OUTPUT_PARSE_FAILED: $Label" }
    return $m.Groups[1].Value
}
function Run-Canonical([string]$Runner, [string]$RawLog) {
    $absolute = Join-Path $RootDir $Runner
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "CANONICAL_RUNNER_MISSING: $Runner" }
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        & $absolute -GodotPath $GodotPath *>&1 | ForEach-Object { $line=[string]$_; $lines.Add($line); Write-Host $line }
    }
    catch {
        $message = ($_ | Out-String).TrimEnd(); if ($message) { $lines.Add($message) }
        $lines | Set-Content -LiteralPath $RawLog -Encoding UTF8
        throw
    }
    $lines | Set-Content -LiteralPath $RawLog -Encoding UTF8
    return $lines -join "`n"
}

if ((Get-GitValue @("branch","--show-current")) -ne $ExpectedBranch) { throw "WRONG_BRANCH: expected=$ExpectedBranch" }
& git -C $RootDir diff --quiet --; if ($LASTEXITCODE -ne 0) { throw "TRACKED_WORKTREE_DIRTY: unstaged changes" }
& git -C $RootDir diff --cached --quiet --; if ($LASTEXITCODE -ne 0) { throw "TRACKED_WORKTREE_DIRTY: staged changes" }

$ObservedBlobs = [ordered]@{}
foreach ($entry in $PinnedSurfaceBlobs.GetEnumerator()) {
    $path=[string]$entry.Key; $expected=[string]$entry.Value
    if (-not (Test-Path -LiteralPath (Join-Path $RootDir $path) -PathType Leaf)) { throw "PINNED_SURFACE_MISSING: $path" }
    $actual=Get-GitValue @("hash-object","--",$path)
    if ($actual -ne $expected) { throw "PINNED_SURFACE_MISMATCH: $path expected=$expected actual=$actual" }
    $ObservedBlobs[$path]=$actual
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath="C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$GodotVersion=(& $GodotPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $GodotVersion -ne $ExpectedGodotVersion) { throw "GODOT_VERSION_MISMATCH: expected=$ExpectedGodotVersion actual=$GodotVersion" }

$Validation=[ordered]@{}; $ValidationBlob=[ordered]@{}; $Accepted=[ordered]@{}
foreach ($key in $Stages.Keys) {
    $Validation[$key]=Read-Validation $Stages[$key].validation
    $ValidationBlob[$key]=Get-GitValue @("hash-object","--",$Stages[$key].validation)
    $Accepted[$key]=Accepted $Validation[$key]
}

$Resolved=$Stage
if ($Resolved -eq "Auto") {
    foreach ($key in $Stages.Keys) { if (-not $Accepted[$key]) { $Resolved=$key; break } }
    if ($Resolved -eq "Auto") { throw "NO_PENDING_P3_CANONICAL_STAGE: P3.1 through P3.8 are already ACCEPTED*" }
}
$Config=$Stages[$Resolved]
$ParentKey=[string]$Config.parent
if ($ParentKey -ne "P28" -and -not $Accepted[$ParentKey]) {
    throw "${Resolved}_CANONICAL_BLOCKED: $ParentKey validation status is not ACCEPTED*: $([string]$Validation[$ParentKey].status)"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot=Join-Path $RootDir "test-results/ecology/p3-windows-canonical" }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$Timestamp=[DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$Head=Get-GitValue @("rev-parse","HEAD"); $Tree=Get-GitValue @("rev-parse","HEAD^{tree}")
$CollectorBlob=Get-GitValue @("hash-object","--","RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1")
$Stem="$Resolved-$Timestamp-$($Head.Substring(0,12))"; $RawLog=Join-Path $OutputRoot "$Stem.log"; $EvidencePath=Join-Path $OutputRoot "$Stem.json"
Write-Host "=== ECO P3 WINDOWS CANONICAL EVIDENCE ==="; Write-Host "stage=$($Config.label)"; Write-Host "head=$Head"; Write-Host "tree=$Tree"; Write-Host "godot=$GodotVersion"; Write-Host "output=$EvidencePath"

$Raw=Run-Canonical $Config.runner $RawLog
if ($Raw -notmatch $Config.marker) { throw "CANONICAL_PASS_MARKER_MISSING: $($Config.label)" }
$Aggregate=Match-One $Raw $Config.aggregate "$($Config.label) aggregate"
$ParentHash=Match-One $Raw $Config.parent_re "$($Config.label) parent"
if ($Aggregate -ne $Aggregates[$Resolved]) { throw "CANONICAL_AGGREGATE_MISMATCH: stage=$($Config.label) expected=$($Aggregates[$Resolved]) actual=$Aggregate" }
if ($ParentHash -ne $Aggregates[$ParentKey]) { throw "CANONICAL_PARENT_MISMATCH: stage=$($Config.label) expected=$($Aggregates[$ParentKey]) actual=$ParentHash" }
$RawSha=(Get-FileHash -LiteralPath $RawLog -Algorithm SHA256).Hash.ToLowerInvariant()

$Control=[ordered]@{ collector_blob=$CollectorBlob; acceptance_mutation_performed=$false }
foreach ($key in $Stages.Keys) { $Control["$($key.ToLower())_validation_blob"]=$ValidationBlob[$key]; $Control["$($key.ToLower())_validation_status"]=[string]$Validation[$key].status }
$Expected=[ordered]@{ p2_8_aggregate_hash=$Aggregates.P28; godot_version=$ExpectedGodotVersion }
foreach ($key in $Stages.Keys) { $Expected["$($key.ToLower())_aggregate_hash"]=$Aggregates[$key] }
$NextAction = if ($Resolved -eq "P38") { "Review this evidence, then accept P3.8 in a separate lifecycle commit; canonical P3.1..P3.8 is then complete." } else { $NextKey=[string]$Config.next; "Review this evidence, then accept $($Config.label) in a separate lifecycle commit before running $($Stages[$NextKey].label) canonical." }

$Evidence=[ordered]@{
    schema="distributed_world_simulator.ecology.p3_windows_canonical_evidence.v1"; result="PASS"; stage=$Config.label; created_utc=[DateTime]::UtcNow.ToString("o")
    repository="rootfabric/distributed-world-simulator"; branch=$ExpectedBranch; head=$Head; tree=$Tree; tracked_worktree_clean=$true
    host=[ordered]@{ os_version=[System.Environment]::OSVersion.VersionString; processor_architecture=[string]$env:PROCESSOR_ARCHITECTURE; powershell_version=$PSVersionTable.PSVersion.ToString(); godot_path=$GodotPath; godot_version=$GodotVersion }
    control=$Control; pinned_surface_blobs=$ObservedBlobs; canonical_runner=$Config.runner
    observed=[ordered]@{ aggregate_hash=$Aggregate; parent_hash=$ParentHash; raw_log=[System.IO.Path]::GetFileName($RawLog); raw_log_sha256=$RawSha }
    expected=$Expected; next_action=$NextAction
}
$Evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8
$EvidenceSha=(Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "ECO.P3 Windows canonical evidence: PASS"; Write-Host "stage=$($Config.label)"; Write-Host "aggregate_hash=$Aggregate"; Write-Host "parent_hash=$ParentHash"; Write-Host "raw_log_sha256=$RawSha"; Write-Host "evidence_sha256=$EvidenceSha"; Write-Host "evidence_json=$EvidencePath"; Write-Host "NOTE: evidence collector performed no validation-status or acceptance mutation."
