param(
    [string]$Repo = "C:\distributed-world-simulator\distributed-world-simulator",
    [string]$GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$WorktreePath = ""
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $Global:PSNativeCommandUseErrorActionPreference = $false
}

$SubjectBranch = "feature/eco-evo7-perf2-conv-stream1-vis4-r3"
$ExpectedHead = "81a0b3fa60664684b02d8387e4693c5f328dbe28"
$ExpectedTree = "a192950483267dd428baf2d1daa25de915df2370"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$ExpectedGodotSha256 = "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
$AcceptedPerf24Head = "840cfcea62ef7192b510235f915b849829654c6c"
$AcceptedPerf24Tree = "967d674c0ba2349db949193969f16f91553761ea"
$AcceptedPerf24Control = "ab115385e81375b224eb397cf6a9de071bd4e79e"
$Vis49Head = "ab44617d8961add81a6c9f245c99d0b68eaeab52"
$Vis49Tree = "9d543a3db4f54a676e9f25152785c36a72c56a30"
$ExpectedArtifactRelative = "artifacts\perf2\perf2-conv-stream1-vis4-r1.json"

function Require-LastExit([string]$Label) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    throw "Repository not found: $Repo"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot not found: $GodotPath"
}

Write-Host "=== PERF2.CONV R3 exact subject fetch ==="
& git -C $Repo fetch origin $SubjectBranch --prune
Require-LastExit "git fetch"
$RemoteHead = (& git -C $Repo rev-parse "refs/remotes/origin/$SubjectBranch").Trim()
Require-LastExit "remote subject resolve"
if ($RemoteHead -ne $ExpectedHead) {
    throw "BLOCKED: origin subject moved: $RemoteHead != $ExpectedHead"
}

$ResolvedTree = (& git -C $Repo rev-parse "$ExpectedHead^{tree}").Trim()
Require-LastExit "subject TREE resolve"
if ($ResolvedTree -ne $ExpectedTree) {
    throw "BLOCKED: subject TREE mismatch: $ResolvedTree != $ExpectedTree"
}

foreach ($Pair in @(
    @($AcceptedPerf24Head, $AcceptedPerf24Tree),
    @($Vis49Head, $Vis49Tree)
)) {
    $Head = $Pair[0]
    $Tree = $Pair[1]
    & git -C $Repo cat-file -e "$Head^{commit}"
    Require-LastExit "prerequisite $Head"
    $ActualTree = (& git -C $Repo rev-parse "$Head^{tree}").Trim()
    if ($ActualTree -ne $Tree) {
        throw "BLOCKED: prerequisite TREE mismatch for $Head"
    }
}
& git -C $Repo cat-file -e "$AcceptedPerf24Control^{commit}"
Require-LastExit "PERF2.4 acceptance control commit"

Write-Host "=== Godot exact identity ==="
$ActualGodot = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "BLOCKED: Godot version mismatch: $ActualGodot != $ExpectedGodot"
}
$ActualGodotSha = (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualGodotSha -ne $ExpectedGodotSha256) {
    throw "BLOCKED: Godot SHA-256 mismatch: $ActualGodotSha != $ExpectedGodotSha256"
}

$Os = Get-CimInstance Win32_OperatingSystem
$Cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$RamGb = [Math]::Round([double]$Os.TotalVisibleMemorySize / 1MB, 2)
$HostDescriptor = "OS=$($Os.Caption)|VERSION=$($Os.Version)|CPU=$($Cpu.Name.Trim())|CORES=$($Cpu.NumberOfCores)|LOGICAL=$($Cpu.NumberOfLogicalProcessors)|RAM_GB=$RamGb"
$Sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $HostFingerprint = ([BitConverter]::ToString($Sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($HostDescriptor)))).Replace("-", "").ToLowerInvariant()
}
finally {
    $Sha.Dispose()
}

if ([string]::IsNullOrWhiteSpace($WorktreePath)) {
    $Parent = Split-Path -Parent $Repo
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $WorktreePath = Join-Path $Parent "dws-perf2-conv-r3-win-$Stamp"
}
if (Test-Path -LiteralPath $WorktreePath) {
    throw "BLOCKED: worktree path already exists: $WorktreePath"
}

Write-Host "=== Fresh detached worktree ==="
& git -C $Repo worktree add --detach $WorktreePath $ExpectedHead
Require-LastExit "git worktree add"
$LocalHead = (& git -C $WorktreePath rev-parse HEAD).Trim()
$LocalTree = (& git -C $WorktreePath rev-parse "HEAD^{tree}").Trim()
$HeadMode = (& git -C $WorktreePath rev-parse --abbrev-ref HEAD).Trim()
if ($LocalHead -ne $ExpectedHead -or $LocalTree -ne $ExpectedTree -or $HeadMode -ne "HEAD") {
    throw "BLOCKED: detached subject identity mismatch"
}

$TrackedBefore = (& git -C $WorktreePath status --porcelain --untracked-files=no)
if ($TrackedBefore) {
    throw "BLOCKED: tracked worktree dirty before verification"
}

$GodotCache = Join-Path $WorktreePath ".godot"
if (Test-Path -LiteralPath $GodotCache) {
    Remove-Item -LiteralPath $GodotCache -Recurse -Force
}

$LogPath = Join-Path $WorktreePath "perf2-conv-r3-win-exact.log"
$Runner = Join-Path $WorktreePath "RUN_ECO_EVO7_PERF2_CONV_TESTS.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "BLOCKED: subject runner missing: $Runner"
}

$PrevHead = $env:ECO_PERF2_CONV_TARGET_HEAD
$PrevTree = $env:ECO_PERF2_CONV_TARGET_TREE
$PrevBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
$PrevGodot = $env:GODOT_BIN
$PrevGodotDouble = $env:GODOT_DOUBLE_BIN

try {
    $env:ECO_PERF2_CONV_TARGET_HEAD = $ExpectedHead
    $env:ECO_PERF2_CONV_TARGET_TREE = $ExpectedTree
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_BIN = $GodotPath
    $env:GODOT_DOUBLE_BIN = $GodotPath

    Write-Host "=== Exact integrated runtime campaign: RUN ONCE ==="
    & $Runner -GodotPath $GodotPath *>&1 | Tee-Object -FilePath $LogPath
}
finally {
    if ($null -eq $PrevHead) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_HEAD -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_HEAD = $PrevHead }
    if ($null -eq $PrevTree) { Remove-Item Env:\ECO_PERF2_CONV_TARGET_TREE -ErrorAction SilentlyContinue } else { $env:ECO_PERF2_CONV_TARGET_TREE = $PrevTree }
    if ($null -eq $PrevBreakpoint) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } else { $env:BREAKPOINT_RUNTIME_DISABLED = $PrevBreakpoint }
    if ($null -eq $PrevGodot) { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_BIN = $PrevGodot }
    if ($null -eq $PrevGodotDouble) { Remove-Item Env:\GODOT_DOUBLE_BIN -ErrorAction SilentlyContinue } else { $env:GODOT_DOUBLE_BIN = $PrevGodotDouble }
}

$LogText = Get-Content -Raw -LiteralPath $LogPath
if (-not $LogText.Contains("ECO.EVO7 PERF2.CONV STREAM1 + VIS4 integrated load: PASS")) {
    throw "VERIFICATION RED: integrated PASS sentinel absent. Do not rerun a completed timing campaign. Inspect $LogPath"
}
if (-not $LogText.Contains("ECO.EVO7 PERF2.CONV STREAM1 + VIS4 candidate: PASS")) {
    throw "VERIFICATION RED: runner PASS sentinel absent"
}

$ArtifactPath = Join-Path $WorktreePath $ExpectedArtifactRelative
if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
    throw "VERIFICATION RED: report artifact missing: $ArtifactPath"
}
$Report = Get-Content -Raw -LiteralPath $ArtifactPath | ConvertFrom-Json
if ($Report.target.head -ne $ExpectedHead -or $Report.target.tree -ne $ExpectedTree) {
    throw "VERIFICATION RED: report target identity mismatch"
}
if (@($Report.samples).Count -ne 36) {
    throw "VERIFICATION RED: expected 36 measured samples"
}
if (@($Report.repetition_summaries).Count -ne 3) {
    throw "VERIFICATION RED: expected 3 repetition summaries"
}
if (-not [bool]$Report.summary.timing_budget_green) { throw "PERFORMANCE RED: timing_budget_green=false" }
if ([double]$Report.summary.p50_combined_to_sim_ratio -gt 2.50) { throw "PERFORMANCE RED: p50 combined/sim > 2.50" }
if ([double]$Report.summary.p95_combined_to_sim_ratio -gt 4.00) { throw "PERFORMANCE RED: p95 combined/sim > 4.00" }
if ([double]$Report.summary.max_combined_ms -gt 5000.0) { throw "PERFORMANCE RED: max combined generation > 5000 ms" }
if (-not [bool]$Report.summary.cache_bounded_green) { throw "CORRECTNESS RED: cache bound failed" }
if (-not [bool]$Report.summary.stream_contract_green) { throw "CORRECTNESS RED: optimized STREAM1 contract failed" }
if (-not [bool]$Report.summary.source_seals_green) { throw "CORRECTNESS RED: source seals failed" }
if (-not [bool]$Report.summary.single_flight_green) { throw "CORRECTNESS RED: single-flight failed" }
if (-not [bool]$Report.summary.foreground_progress_green) { throw "CORRECTNESS RED: foreground progress failed" }

foreach ($Claim in @(
    "perf2_5_vis4_materialization_profiling",
    "perf2_6_ph5_lod_cache_bounded",
    "perf2_7_stream1_vis4_integrated_load",
    "perf2_8_play1_performance_acceptance"
)) {
    if (-not [bool]$Report.claims.$Claim) {
        throw "VERIFICATION RED: claim not green: $Claim"
    }
}

$FinalHead = (& git -C $WorktreePath rev-parse HEAD).Trim()
$FinalTree = (& git -C $WorktreePath rev-parse "HEAD^{tree}").Trim()
$TrackedAfter = (& git -C $WorktreePath status --porcelain --untracked-files=no)
if ($FinalHead -ne $ExpectedHead -or $FinalTree -ne $ExpectedTree) {
    throw "BLOCKED: subject moved during verification"
}
if ($TrackedAfter) {
    throw "BLOCKED: tracked worktree changed during verification"
}

$ArtifactFileSha = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host ""
Write-Host "PERF2.CONV R3 WINDOWS EXACT VERIFICATION COMPLETED: PASS"
Write-Host "subject_head=$ExpectedHead"
Write-Host "subject_tree=$ExpectedTree"
Write-Host "godot=$ActualGodot"
Write-Host "godot_sha256=$ActualGodotSha"
Write-Host "host_descriptor=$HostDescriptor"
Write-Host "host_fingerprint=$HostFingerprint"
Write-Host "samples=$(@($Report.samples).Count)"
Write-Host "repetitions=$(@($Report.repetition_summaries).Count)"
Write-Host "p50_combined_to_sim_ratio=$($Report.summary.p50_combined_to_sim_ratio)"
Write-Host "p95_combined_to_sim_ratio=$($Report.summary.p95_combined_to_sim_ratio)"
Write-Host "p50_combined_ms=$($Report.summary.p50_combined_ms)"
Write-Host "p95_combined_ms=$($Report.summary.p95_combined_ms)"
Write-Host "p50_simulation_ms=$($Report.summary.p50_simulation_ms)"
Write-Host "p95_simulation_ms=$($Report.summary.p95_simulation_ms)"
Write-Host "p50_presentation_overhead_ms=$($Report.summary.p50_presentation_overhead_ms)"
Write-Host "p95_presentation_overhead_ms=$($Report.summary.p95_presentation_overhead_ms)"
Write-Host "max_combined_ms=$($Report.summary.max_combined_ms)"
Write-Host "max_cache_entries=$($Report.summary.max_cache_entries)"
Write-Host "max_record_count=$($Report.summary.max_record_count)"
Write-Host "min_foreground_frames=$($Report.summary.min_foreground_frames)"
Write-Host "report_hash=$($Report.report_hash)"
Write-Host "artifact_file_sha256=$ArtifactFileSha"
Write-Host "log=$LogPath"
Write-Host "artifact=$ArtifactPath"
Write-Host "tracked_clean=YES"
Write-Host ""
Write-Host "Работа закончена. Следующий шаг: передать этот PASS и report_hash для формального PERF2.CONV acceptance."
