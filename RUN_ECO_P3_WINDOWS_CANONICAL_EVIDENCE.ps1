param(
    [ValidateSet("Auto", "P31", "P32")]
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

$PinnedSurfaceBlobs = [ordered]@{
    "RUN_ECO_EVO1_P2_8_TESTS.ps1" = "2f263f562bbdde60e2cf2868c1bb30dd49ed4835"
    "RUN_ECO_P3_1_TESTS.ps1" = "3a4f1cf35f530da08485638cd907283cd9d6cc30"
    "scripts/research/ecology/plant_resource_competition_v1.gd" = "c667569b40775a1a1898d7b911a610ca5795f380"
    "tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd" = "421bf16651da64f92690ba2d676ecee7b3f97cf0"
    "RUN_ECO_P3_2_TESTS.ps1" = "9056e180bf806547b6ecd8ae9a75f8cc83fccdfc"
    "scripts/research/ecology/plant_density_carrying_capacity_v1.gd" = "8e635f8915ad53cac9a37917df32036cf92907b2"
    "tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd" = "c07e2c211ac9a5bf8ce58f323b3684b1e1e04028"
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
$p31Accepted = Test-AcceptedStatus $p31Validation
$p32Accepted = Test-AcceptedStatus $p32Validation

$resolvedStage = $Stage
if ($resolvedStage -eq "Auto") {
    if (-not $p31Accepted) {
        $resolvedStage = "P31"
    }
    elseif (-not $p32Accepted) {
        $resolvedStage = "P32"
    }
    else {
        throw "NO_PENDING_P3_CANONICAL_STAGE: P3.1 and P3.2 are already ACCEPTED*"
    }
}
if ($resolvedStage -eq "P32" -and -not $p31Accepted) {
    throw "P3_2_CANONICAL_BLOCKED: P3.1 validation status is not ACCEPTED*: $([string]$p31Validation.status)"
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
$stageLabel = if ($resolvedStage -eq "P31") { "P3.1" } else { "P3.2" }
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
else {
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

$rawLogSha256 = (Get-FileHash -LiteralPath $RawLogPath -Algorithm SHA256).Hash.ToLowerInvariant()
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
        godot_version = $ExpectedGodotVersion
    }
    next_action = if ($resolvedStage -eq "P31") {
        "Review this exact evidence, then update P3.1 validation to ACCEPTED in a separate lifecycle commit before running P3.2 canonical."
    }
    else {
        "Review this exact evidence, then update P3.2 validation to ACCEPTED in a separate lifecycle commit before opening P3.3."
    }
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
