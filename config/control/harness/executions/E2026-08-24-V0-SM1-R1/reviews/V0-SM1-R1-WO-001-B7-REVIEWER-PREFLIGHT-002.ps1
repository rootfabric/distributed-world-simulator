param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"

$SubjectHead = "b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f"
$SubjectTree = "7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68"
$OldReviewHead = "6fdfc047f54e727e6b398370e576c746c7949441"
$R7Head = "baa0e192209e72aba5ae9d04663eea85b1099e82"
$R8Head = "25f5ddf6280a39a44ddfc3bbec5245873021c0a1"
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"
$VerificationPath = "config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-003.v1.json"
$VerificationRef = "origin/control/v0-sm1-b6-r9-verification-003-r1"
$BarrierPath = "scripts/runtime/networked_gameplay/m5/m5_convergence_barrier.gd"
$WorkerPath = "tools/runtime/m7_playable_network_client.gd"
$M7TestPath = "tests/runtime/test_m7_playable_networked_processes.gd"

$ExpectedR9Paths = @(
    "tests/runtime/test_m7_playable_networked_processes.gd",
    "tools/runtime/m7_playable_network_client.gd"
)

$ExpectedOldToR9Paths = @(
    "RUN_M5_GRAPHICAL_STABILITY_TESTS.ps1",
    "RUN_NETWORK_CONTRACT_TESTS.ps1",
    "scripts/runtime/networked_gameplay/m5/m5_convergence_barrier.gd",
    "scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd",
    "scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd",
    "scripts/runtime/networked_gameplay/m5/m5_process_environment.gd",
    "scripts/testing/process_harness/atomic_json_file.gd",
    "tests/runtime/support/m5_control_read_consistency_regression.gd",
    "tests/runtime/support/m5_convergence_release_guard_regression.gd",
    "tests/runtime/test_m5_graphical_acceptance_contracts.gd",
    "tests/runtime/test_m5_graphical_multiplayer_acceptance.gd",
    "tests/runtime/test_m7_playable_networked_processes.gd",
    "tools/runtime/m7_playable_network_client.gd"
)

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Name)
    if ($Actual -ne $Expected) {
        throw "$Name mismatch: actual=[$Actual] expected=[$Expected]"
    }
}

function Assert-PathSet {
    param([string[]]$Actual, [string[]]$Expected, [string]$Name)
    $Diff = @(Compare-Object ($Expected | Sort-Object) ($Actual | Sort-Object))
    if ($Diff.Count -ne 0) {
        Write-Host "$Name mismatch:" -ForegroundColor Red
        $Diff | Format-Table | Out-String | Write-Host
        throw "$Name path-set mismatch"
    }
}

$Report = [ordered]@{
    schema = "distributed_world_simulator.v0_sm1_b7_reviewer_preflight.v1"
    subject_head = $SubjectHead
    subject_tree = $SubjectTree
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    checks = [ordered]@{}
}

# Exact identity
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
$StatusBefore = @(git status --porcelain)
Assert-Equal $Head $SubjectHead "HEAD"
Assert-Equal $Tree $SubjectTree "TREE"
Assert-Equal $StatusBefore.Count 0 "clean-before"
$Report.checks.subject_identity = @{ result = "PASS"; head = $Head; tree = $Tree; clean = $true }

# Ancestry and composition
git merge-base --is-ancestor $OldReviewHead $SubjectHead
if ($LASTEXITCODE -ne 0) { throw "OLD_REVIEW_HEAD_NOT_ANCESTOR" }
git merge-base --is-ancestor $R7Head $SubjectHead
if ($LASTEXITCODE -ne 0) { throw "R7_NOT_ANCESTOR" }
git merge-base --is-ancestor $R8Head $SubjectHead
if ($LASTEXITCODE -ne 0) { throw "R8_NOT_ANCESTOR" }

$OldCount = [int]((git rev-list --count "$OldReviewHead..$SubjectHead").Trim())
$R7Count = [int]((git rev-list --count "$R7Head..$SubjectHead").Trim())
$R8Count = [int]((git rev-list --count "$R8Head..$SubjectHead").Trim())
Assert-Equal $OldCount 48 "old->R9 commit count"
Assert-Equal $R7Count 9 "R7->R9 commit count"
Assert-Equal $R8Count 2 "R8->R9 commit count"

$R9Paths = @(git diff --name-only "$R8Head..$SubjectHead")
$OldPaths = @(git diff --name-only "$OldReviewHead..$SubjectHead")
Assert-PathSet $R9Paths $ExpectedR9Paths "R8->R9"
Assert-PathSet $OldPaths $ExpectedOldToR9Paths "OLD_REVIEW->R9"
$Report.checks.composition = @{ result = "PASS"; old_to_r9 = $OldCount; r7_to_r9 = $R7Count; r8_to_r9 = $R8Count; old_delta_files = $OldPaths.Count; r9_delta_files = $R9Paths.Count }

# Barrier must be byte-identical from R7 through R9.
git diff --quiet $R7Head $SubjectHead -- $BarrierPath
if ($LASTEXITCODE -ne 0) { throw "M5_CONVERGENCE_BARRIER_CHANGED_R7_TO_R9" }
$Report.checks.r7_barrier_identity = @{ result = "PASS"; path = $BarrierPath }

# R9 camera-basis guards
$Worker = Get-Content -LiteralPath $WorkerPath -Raw
$M7Test = Get-Content -LiteralPath $M7TestPath -Raw
if ($Worker -notmatch 'func _set_automated_camera_yaw') { throw "R9_CAMERA_HELPER_MISSING" }
if ($Worker -notmatch 'wrapf\(desired_yaw - current_yaw, -PI, PI\)') { throw "R9_WRAPPED_YAW_DELTA_MISSING" }
if ($Worker -notmatch 'playground\.player\.adjust_view\(yaw_delta, 0\.0\)') { throw "R9_ADJUST_VIEW_MISSING" }
if ($Worker -match 'playground\.player\.camera_yaw\s*=') { throw "R9_DIRECT_CAMERA_YAW_ASSIGNMENT_PRESENT" }
if ($M7Test -notmatch '_set_automated_camera_yaw') { throw "R9_M7_SOURCE_GUARD_HELPER_MISSING" }
if ($M7Test -notmatch 'adjust_view\(yaw_delta, 0\.0\)') { throw "R9_M7_SOURCE_GUARD_ADJUST_VIEW_MISSING" }
if ($M7Test -notmatch 'camera_yaw =') { throw "R9_M7_SOURCE_GUARD_DIRECT_ASSIGNMENT_BAN_MISSING" }
$Report.checks.r9_camera_basis = @{ result = "PASS"; direct_assignment_absent = $true; public_adjust_view = $true; source_guards = $true }

# VERIFICATION-003 integrity. The record is control-only evidence and must not be
# materialized into the immutable runtime subject. Read it directly from its
# remote-tracking ref after fetch.
git fetch origin --prune | Out-Host
$VerificationRaw = git show "${VerificationRef}:$VerificationPath"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($VerificationRaw -join "`n"))) {
    throw "VERIFICATION_003_UNAVAILABLE_FROM_CONTROL_REF"
}
$Verification = (($VerificationRaw -join "`n").TrimStart([char]0xFEFF)) | ConvertFrom-Json
Assert-Equal $Verification.verdict "VERIFIED" "VERIFICATION-003 verdict"
Assert-Equal $Verification.verified_head_sha $SubjectHead "VERIFICATION-003 head"
Assert-Equal $Verification.verified_tree_sha $SubjectTree "VERIFICATION-003 tree"
Assert-Equal $Verification.checks.r9_m7_decisive_10x.result "PASS_10_OF_10" "VERIFICATION-003 M7"
Assert-Equal $Verification.checks.m5_decisive_10x.passed 10 "VERIFICATION-003 M5 passes"
Assert-Equal $Verification.checks.focused_sm1.result "PASS_13_OF_13" "VERIFICATION-003 SM1"
Assert-Equal $Verification.checks.repeated_impaired_network_5x.result "PASS_5_OF_5" "VERIFICATION-003 impaired"
Assert-Equal $Verification.checks.full_world_core_regression.summary.passed $true "VERIFICATION-003 canonical"
Assert-Equal $Verification.checks.full_world_core_regression.summary.declared_test_count 304 "VERIFICATION-003 declared"
Assert-Equal $Verification.checks.full_world_core_regression.summary.discovered_test_count 304 "VERIFICATION-003 discovered"
Assert-Equal $Verification.checks.full_world_core_regression.summary.steps_recorded 307 "VERIFICATION-003 steps"
Assert-Equal $Verification.checks.full_world_core_regression.summary.bad_exit_code_steps 0 "VERIFICATION-003 bad exits"
$Report.checks.verification_003 = @{ result = "PASS"; verdict = $Verification.verdict; exact_subject = $true; canonical = "304/304 307 steps 0 bad" }

# Optional exact Godot identity if path supplied/resolved.
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $GodotPath = $env:GODOT_BIN }
}
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
    $VersionOutput = & $GodotPath --version 2>&1
    $Version = ($VersionOutput | Select-Object -First 1).ToString().Trim()
    Assert-Equal $Version $ExpectedGodot "Godot identity"
    $global:LASTEXITCODE = 0
    $Report.checks.godot = @{ result = "PASS"; version = $Version; path = $GodotPath }
} else {
    $Report.checks.godot = @{ result = "NOT_RUN"; reason = "GodotPath/GODOT_BIN not supplied" }
}

# Current PC0 is reviewer evidence, not a GREEN assertion.
git fetch origin --prune | Out-Host
& .\CONTROL_PROJECT.ps1 -NoFailOnRed
if ($LASTEXITCODE -ne 0) { throw "CONTROL_PROJECT_INVOCATION_FAILED" }
$ProjectControlPath = "artifacts/control/project-control-report.json"
$DirectionalPath = "artifacts/control/directional-watch-report.json"
if (-not (Test-Path $ProjectControlPath)) { throw "PROJECT_CONTROL_REPORT_MISSING" }
if (-not (Test-Path $DirectionalPath)) { throw "DIRECTIONAL_REPORT_MISSING" }
$PC = (Get-Content $ProjectControlPath -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
$DW = (Get-Content $DirectionalPath -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
$Report.checks.pc0 = @{
    result = "CAPTURED"
    standard_overall = $PC.overall
    directional_overall = $DW.overall
    report_paths = @($ProjectControlPath, $DirectionalPath)
}

# Final freshness
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()
git diff --exit-code | Out-Null
$Tracked = $LASTEXITCODE
git diff --cached --exit-code | Out-Null
$Staged = $LASTEXITCODE
Assert-Equal $FinalHead $SubjectHead "final HEAD"
Assert-Equal $FinalTree $SubjectTree "final TREE"
Assert-Equal $Tracked 0 "tracked diff"
Assert-Equal $Staged 0 "staged diff"
$Report.checks.freshness = @{ result = "PASS"; head = $FinalHead; tree = $FinalTree; tracked_clean = $true; staged_clean = $true }

$OutputDir = "artifacts/control"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputPath = Join-Path $OutputDir "v0-sm1-b7-r9-reviewer-preflight.json"
$Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host ""
Write-Host "B7_R9_REVIEWER_PREFLIGHT_PASS" -ForegroundColor Green
Write-Host "Report: $OutputPath"
Write-Host "This is deterministic preflight evidence only; it is NOT an independent Reviewer verdict."
