param(
    [ValidateSet("Auto", "P31", "P32", "P33", "P34", "P35")]
    [string]$Stage = "Auto",
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/eco-evolutionary-ecology"
$ExpectedGodotVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedP28Aggregate = "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"
$ExpectedP31Aggregate = "f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a"
$ExpectedP32Aggregate = "172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639"
$ExpectedP33Aggregate = "37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41"
$ExpectedP34Aggregate = "a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813"
$ExpectedP35Aggregate = "255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83"

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
}

function Get-GitValue([string[]]$Arguments) {
    $value = (& git -C $RootDir @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $value"
    }
    return $value
}

function Assert-TrackedWorktreeClean() {
    & git -C $RootDir diff --quiet --
    if ($LASTEXITCODE -ne 0) {
        throw "TRACKED_WORKTREE_DIRTY: unstaged tracked changes are present"
    }
    & git -C $RootDir diff --cached --quiet --
    if ($LASTEXITCODE -ne 0) {
        throw "TRACKED_WORKTREE_DIRTY: staged changes are present"
    }
}

function Assert-PinnedSurfaceBlobs() {
    $observed = [ordered]@{}
    foreach ($entry in $PinnedSurfaceBlobs.GetEnumerator()) {
        $relativePath = [string]$entry.Key
        $expected = [string]$entry.Value
        $absolutePath = Join-Path $RootDir $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            throw "PINNED_SURFACE_MISSING: $relativePath"
        }
        $actual = Get-GitValue -Arguments @("hash-object", "--", $relativePath)
        if ($actual -ne $expected) {
            throw "PINNED_SURFACE_MISMATCH: $relativePath expected=$expected actual=$actual"
        }
        $observed[$relativePath] = $actual
    }
    return $observed
}

function Read-Validation([string]$RelativePath) {
    $path = Join-Path $RootDir $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "VALIDATION_FILE_MISSING: $RelativePath"
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Test-AcceptedStatus([object]$Validation) {
    $status = [string]$Validation.status
    return $status.StartsWith("ACCEPTED", [System.StringComparison]::Ordinal)
}

function Invoke-CanonicalRunner([string]$RunnerPath, [string]$RawLogPath) {
    $absoluteRunner = Join-Path $RootDir $RunnerPath
    if (-not (Test-Path -LiteralPath $absoluteRunner -PathType Leaf)) {
        throw "CANONICAL_RUNNER_MISSING: $RunnerPath"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        & $absoluteRunner -GodotPath $GodotPath *>&1 | ForEach-Object {
            $line = [string]$_
            $lines.Add($line)
            Write-Host $line
        }
    }
    catch {
        $message = ($_ | Out-String).TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $lines.Add($message)
        }
        $lines | Set-Content -LiteralPath $RawLogPath -Encoding UTF8
        throw
    }
    $lines | Set-Content -LiteralPath $RawLogPath -Encoding UTF8
    return ($lines -join "`n")
}

function Require-Match([string]$Text, [string]$Pattern, [string]$Label) {
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        throw "CANONICAL_OUTPUT_PARSE_FAILED: $Label"
    }
    return $match.Groups[1].Value
}

$currentBranch = Get-GitValue -Arguments @("branch", "--show-current")
if ($currentBranch -ne $ExpectedBranch) {
    throw "WRONG_BRANCH: expected=$ExpectedBranch actual=$currentBranch"
}

Assert-TrackedWorktreeClean
$surfaceBlobs = Assert-PinnedSurfaceBlobs

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$godotVersion = (& $GodotPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to execute Godot --version"
}
if ($godotVersion -ne $ExpectedGodotVersion) {
    throw "GODOT_VERSION_MISMATCH: expected=$ExpectedGodotVersion actual=$godotVersion"
}

$p31Validation = Read-Validation "validation/ecology/eco-p3-1-resource-competition-validation.json"
$p32Validation = Read-Validation "validation/ecology/eco-p3-2-density-carrying-capacity-validation.json"
$p33Validation = Read-Validation "validation/ecology/eco-p3-3-spatial-dispersal-validation.json"
$p34Validation = Read-Validation "validation/ecology/eco-p3-4-environmental-gradient-validation.json"
$p35Validation = Read-Validation "validation/ecology/eco-p3-5-seasonal-world-validation.json"
$p31Accepted = Test-AcceptedStatus $p31Validation
$p32Accepted = Test-AcceptedStatus $p32Validation
$p33Accepted = Test-AcceptedStatus $p33Validation
$p34Accepted = Test-AcceptedStatus $p34Validation
$p35Accepted = Test-AcceptedStatus $p35Validation

$resolvedStage = $Stage
if ($resolvedStage -eq "Auto") {
    if (-not $p31Accepted) {
        $resolvedStage = "P31"
    }
    elseif (-not $p32Accepted) {
        $resolvedStage = "P32"
    }
    elseif (-not $p33Accepted) {
        $resolvedStage = "P33"
    }
    elseif (-not $p34Accepted) {
        $resolvedStage = "P34"
    }
    elseif (-not $p35Accepted) {
        $resolvedStage = "P35"
    }
    else {
        throw "NO_PENDING_P3_CANONICAL_STAGE: P3.1 through P3.5 are already ACCEPTED*"
    }
}
if ($resolvedStage -eq "P32" -and -not $p31Accepted) {
    throw "P3_2_CANONICAL_BLOCKED: P3.1 validation status is not ACCEPTED*: $([string]$p31Validation.status)"
}
if ($resolvedStage -eq "P33" -and -not $p32Accepted) {
    throw "P3_3_CANONICAL_BLOCKED: P3.2 validation status is not ACCEPTED*: $([string]$p32Validation.status)"
}
if ($resolvedStage -eq "P34" -and -not $p33Accepted) {
    throw "P3_4_CANONICAL_BLOCKED: P3.3 validation status is not ACCEPTED*: $([string]$p33Validation.status)"
}
if ($resolvedStage -eq "P35" -and -not $p34Accepted) {
    throw "P3_5_CANONICAL_BLOCKED: P3.4 validation status is not ACCEPTED*: $([string]$p34Validation.status)"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RootDir "test-results/ecology/p3-windows-canonical"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$head = Get-GitValue -Arguments @("rev-parse", "HEAD")
$tree = Get-GitValue -Arguments @("rev-parse", "HEAD^{tree}")
$collectorBlob = Get-GitValue -Arguments @("hash-object", "--", "RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1")
$validationP31Blob = Get-GitValue -Arguments @("hash-object", "--", "validation/ecology/eco-p3-1-resource-competition-validation.json")
$validationP32Blob = Get-GitValue -Arguments @("hash-object", "--", "validation/ecology/eco-p3-2-density-carrying-capacity-validation.json")
$validationP33Blob = Get-GitValue -Arguments @("hash-object", "--", "validation/ecology/eco-p3-3-spatial-dispersal-validation.json")
$validationP34Blob = Get-GitValue -Arguments @("hash-object", "--", "validation/ecology/eco-p3-4-environmental-gradient-validation.json")
$validationP35Blob = Get-GitValue -Arguments @("hash-object", "--", "validation/ecology/eco-p3-5-seasonal-world-validation.json")
$stageLabel = switch ($resolvedStage) {
    "P31" { "P3.1" }
    "P32" { "P3.2" }
    "P33" { "P3.3" }
    "P34" { "P3.4" }
    "P35" { "P3.5" }
    default { throw "UNSUPPORTED_RESOLVED_STAGE: $resolvedStage" }
}
$fileStem = "$resolvedStage-$timestamp-$($head.Substring(0, 12))"
$rawLogPath = Join-Path $OutputRoot "$fileStem.log"
$evidencePath = Join-Path $OutputRoot "$fileStem.json"

Write-Host "=== ECO P3 WINDOWS CANONICAL EVIDENCE ==="
Write-Host "stage=$stageLabel"
Write-Host "head=$head"
Write-Host "tree=$tree"
Write-Host "godot=$godotVersion"
Write-Host "output=$evidencePath"

$runner = ""
$aggregate = ""
$parentHash = ""
$rawOutput = ""
if ($resolvedStage -eq "P31") {
    $runner = "RUN_ECO_P3_1_TESTS.ps1"
    $rawOutput = Invoke-CanonicalRunner $runner $rawLogPath
    if ($rawOutput -notmatch 'ECO\.P3\.1 candidate automated gates: PASS') {
        throw "P3_1_CANONICAL_PASS_MARKER_MISSING"
    }
    $aggregate = Require-Match $rawOutput 'ECO\.P3\.1 aggregate_hash=([0-9a-f]{64})' "P3.1 aggregate"
    $parentHash = Require-Match $rawOutput 'ECO\.P3\.1 parent_p2_8=([0-9a-f]{64})' "P3.1 parent P2.8"
    if ($aggregate -ne $ExpectedP31Aggregate) {
        throw "P3_1_AGGREGATE_MISMATCH: expected=$ExpectedP31Aggregate actual=$aggregate"
    }
    if ($parentHash -ne $ExpectedP28Aggregate) {
        throw "P3_1_PARENT_MISMATCH: expected=$ExpectedP28Aggregate actual=$parentHash"
    }
}
elseif ($resolvedStage -eq "P32") {
    $runner = "RUN_ECO_P3_2_TESTS.ps1"
    $rawOutput = Invoke-CanonicalRunner $runner $rawLogPath
    if ($rawOutput -notmatch 'ECO\.P3\.2 candidate automated gates: PASS') {
        throw "P3_2_CANONICAL_PASS_MARKER_MISSING"
    }
    $aggregate = Require-Match $rawOutput 'ECO\.P3\.2 aggregate_hash=([0-9a-f]{64})' "P3.2 aggregate"
    $parentHash = Require-Match $rawOutput 'ECO\.P3\.2 parent_p3_1=([0-9a-f]{64})' "P3.2 parent P3.1"
    if ($aggregate -ne $ExpectedP32Aggregate) {
        throw "P3_2_AGGREGATE_MISMATCH: expected=$ExpectedP32Aggregate actual=$aggregate"
    }
    if ($parentHash -ne $ExpectedP31Aggregate) {
        throw "P3_2_PARENT_MISMATCH: expected=$ExpectedP31Aggregate actual=$parentHash"
    }
}
elseif ($resolvedStage -eq "P33") {
    $runner = "RUN_ECO_P3_3_TESTS.ps1"
    $rawOutput = Invoke-CanonicalRunner $runner $rawLogPath
    if ($rawOutput -notmatch 'ECO\.P3\.3 candidate automated gates: PASS') { throw "P3_3_CANONICAL_PASS_MARKER_MISSING" }
    $aggregate = Require-Match $rawOutput 'ECO\.P3\.3 aggregate_hash=([0-9a-f]{64})' "P3.3 aggregate"
    $parentHash = Require-Match $rawOutput 'ECO\.P3\.3 parent_p3_2=([0-9a-f]{64})' "P3.3 parent P3.2"
    if ($aggregate -ne $ExpectedP33Aggregate) { throw "P3_3_AGGREGATE_MISMATCH: expected=$ExpectedP33Aggregate actual=$aggregate" }
    if ($parentHash -ne $ExpectedP32Aggregate) { throw "P3_3_PARENT_MISMATCH: expected=$ExpectedP32Aggregate actual=$parentHash" }
}
elseif ($resolvedStage -eq "P34") {
    $runner = "RUN_ECO_P3_4_TESTS.ps1"
    $rawOutput = Invoke-CanonicalRunner $runner $rawLogPath
    if ($rawOutput -notmatch 'ECO\.P3\.4 candidate automated gates: PASS') { throw "P3_4_CANONICAL_PASS_MARKER_MISSING" }
    $aggregate = Require-Match $rawOutput 'ECO\.P3\.4 aggregate_hash=([0-9a-f]{64})' "P3.4 aggregate"
    $parentHash = Require-Match $rawOutput 'ECO\.P3\.4 parent_p3_3=([0-9a-f]{64})' "P3.4 parent P3.3"
    if ($aggregate -ne $ExpectedP34Aggregate) { throw "P3_4_AGGREGATE_MISMATCH: expected=$ExpectedP34Aggregate actual=$aggregate" }
    if ($parentHash -ne $ExpectedP33Aggregate) { throw "P3_4_PARENT_MISMATCH: expected=$ExpectedP33Aggregate actual=$parentHash" }
}
else {
    $runner = "RUN_ECO_P3_5_TESTS.ps1"
    $rawOutput = Invoke-CanonicalRunner $runner $rawLogPath
    if ($rawOutput -notmatch 'ECO\.P3\.5 candidate automated gates: PASS') { throw "P3_5_CANONICAL_PASS_MARKER_MISSING" }
    $aggregate = Require-Match $rawOutput 'ECO\.P3\.5 aggregate_hash=([0-9a-f]{64})' "P3.5 aggregate"
    $parentHash = Require-Match $rawOutput 'ECO\.P3\.5 parent_p3_4=([0-9a-f]{64})' "P3.5 parent P3.4"
    if ($aggregate -ne $ExpectedP35Aggregate) { throw "P3_5_AGGREGATE_MISMATCH: expected=$ExpectedP35Aggregate actual=$aggregate" }
    if ($parentHash -ne $ExpectedP34Aggregate) { throw "P3_5_PARENT_MISMATCH: expected=$ExpectedP34Aggregate actual=$parentHash" }
}

$rawLogSha256 = (Get-FileHash -LiteralPath $RawLogPath -Algorithm SHA256).Hash.ToLowerInvariant()
$nextAction = switch ($resolvedStage) {
    "P31" { "Review this exact evidence, then update P3.1 validation to ACCEPTED in a separate lifecycle commit before running P3.2 canonical." }
    "P32" { "Review this exact evidence, then update P3.2 validation to ACCEPTED in a separate lifecycle commit before opening/running P3.3." }
    "P33" { "Review this exact evidence, then update P3.3 validation to ACCEPTED in a separate lifecycle commit before running P3.4 canonical." }
    "P34" { "Review this exact evidence, then update P3.4 validation to ACCEPTED in a separate lifecycle commit before running P3.5 canonical." }
    "P35" { "Review this exact evidence, then update P3.5 validation to ACCEPTED in a separate lifecycle commit before opening P3.6 Disturbance & Succession." }
    default { throw "UNSUPPORTED_RESOLVED_STAGE: $resolvedStage" }
}

$evidence = [ordered]@{
    schema = "distributed_world_simulator.ecology.p3_windows_canonical_evidence.v1"
    result = "PASS"
    stage = $stageLabel
    created_utc = [DateTime]::UtcNow.ToString("o")
    repository = "rootfabric/distributed-world-simulator"
    branch = $currentBranch
    head = $head
    tree = $tree
    tracked_worktree_clean = $true
    host = [ordered]@{
        os_version = [System.Environment]::OSVersion.VersionString
        processor_architecture = [string]$env:PROCESSOR_ARCHITECTURE
        powershell_version = $PSVersionTable.PSVersion.ToString()
        godot_path = $GodotPath
        godot_version = $godotVersion
    }
    control = [ordered]@{
        collector_blob = $collectorBlob
        p31_validation_blob = $validationP31Blob
        p31_validation_status = [string]$p31Validation.status
        p32_validation_blob = $validationP32Blob
        p32_validation_status = [string]$p32Validation.status
        p33_validation_blob = $validationP33Blob
        p33_validation_status = [string]$p33Validation.status
        p34_validation_blob = $validationP34Blob
        p34_validation_status = [string]$p34Validation.status
        p35_validation_blob = $validationP35Blob
        p35_validation_status = [string]$p35Validation.status
        acceptance_mutation_performed = $false
    }
    pinned_surface_blobs = $surfaceBlobs
    canonical_runner = $runner
    observed = [ordered]@{
        aggregate_hash = $aggregate
        parent_hash = $parentHash
        raw_log = [System.IO.Path]::GetFileName($rawLogPath)
        raw_log_sha256 = $rawLogSha256
    }
    expected = [ordered]@{
        p2_8_aggregate_hash = $ExpectedP28Aggregate
        p3_1_aggregate_hash = $ExpectedP31Aggregate
        p3_2_aggregate_hash = $ExpectedP32Aggregate
        p3_3_aggregate_hash = $ExpectedP33Aggregate
        p3_4_aggregate_hash = $ExpectedP34Aggregate
        p3_5_aggregate_hash = $ExpectedP35Aggregate
        godot_version = $ExpectedGodotVersion
    }
    next_action = $nextAction
}

$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
$evidenceSha256 = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "ECO.P3 Windows canonical evidence: PASS"
Write-Host "stage=$stageLabel"
Write-Host "aggregate_hash=$aggregate"
Write-Host "parent_hash=$parentHash"
Write-Host "raw_log_sha256=$rawLogSha256"
Write-Host "evidence_sha256=$evidenceSha256"
Write-Host "evidence_json=$evidencePath"
Write-Host "NOTE: evidence collector performed no validation-status or acceptance mutation."
