param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedBranch = "feature/g8-geomorphology"
$ExpectedGlobalRevision = "GLOBAL-P0-2026-08-10-R2"
$ExpectedControlRevision = "PC0-2026-08-10-R1"
$G86AcceptedMetadataCommit = "f2c5b99ee3940e2515ab758ab3077ff09bf081fd"
$G86AutomatedTestedHead = "a9ca1f8b723e4edc5ebff40db26e41283d464597"
$G86ManualObservedHead = "b91ed3eb8664ec1aee28453947a84c6a56acb95b"
$ExpectedTruthHash = "36c87791f25bbd0b"
$ControlReportPath = Join-Path $RootDir "artifacts\control\project-control-report.json"
$WindowsProfileTransientPath = Join-Path $RootDir "Microsoft"

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $Output = & git -C $RootDir @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($Output | Out-String)"
    }
    return (($Output | Out-String).Trim())
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ([string]$Actual -ne [string]$Expected) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Invoke-PowerShellChild {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ScriptArguments = @()
    )
    $PowerShellExecutable = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($PowerShellExecutable) -or -not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        throw "Could not resolve current PowerShell executable"
    }
    & $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Child PowerShell runner failed: $ScriptPath (exit $LASTEXITCODE)"
    }
}

function Test-WindowsProfileTransientSafeToRemove {
    if (-not (Test-Path -LiteralPath $WindowsProfileTransientPath)) { return $false }
    $TrackedEntries = (& git -C $RootDir ls-files -- "Microsoft" 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($TrackedEntries)) { return $false }
    $StatusText = (& git -C $RootDir status --porcelain --untracked-files=all -- "Microsoft" 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($StatusText)) { return $false }
    foreach ($Line in @($StatusText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not $Line.StartsWith("?? Microsoft/")) { return $false }
    }
    return $true
}

function Remove-SafeWindowsProfileTransient {
    param([Parameter(Mandatory = $true)][string]$Phase)
    if (-not (Test-Path -LiteralPath $WindowsProfileTransientPath)) { return }
    if (-not (Test-WindowsProfileTransientSafeToRemove)) {
        Write-Warning "Refusing to clean Microsoft/ during $Phase because it is not proven transient"
        return
    }
    Remove-Item -LiteralPath $WindowsProfileTransientPath -Recurse -Force -ErrorAction Stop
    Write-Host "Removed $Phase Windows profile transient directory: Microsoft/"
}

function Test-G8AggregateAllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return $Path -in @(
        "RUN_G8_FULL_ACCEPTANCE.ps1",
        "config/control/branches/feature__g8-geomorphology.v1.json",
        "docs/checkpoints/G8_FULL_ACCEPTANCE_CANDIDATE_RU.md",
        "validation/g8-full-acceptance-validation.json"
    )
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required for G8 Full Acceptance"
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "=== G8 FULL ACCEPTANCE: repository preflight ==="
Remove-SafeWindowsProfileTransient -Phase "stale-preflight"
$CurrentBranch = Invoke-GitText @("rev-parse", "--abbrev-ref", "HEAD")
Assert-Equal $CurrentBranch $ExpectedBranch "G8 Full Acceptance must run from the G branch"
$CurrentHead = Invoke-GitText @("rev-parse", "HEAD")
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) {
    throw "G8 Full Acceptance requires a clean working tree:`n$StatusBefore"
}
foreach ($Ref in @("origin/main", $G86AcceptedMetadataCommit, $G86AutomatedTestedHead, $G86ManualObservedHead)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref/commit $Ref. Run git fetch origin first." }
}
& git -C $RootDir merge-base --is-ancestor $G86AcceptedMetadataCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "Accepted G8.6 metadata commit is not an ancestor of current checkout" }
& git -C $RootDir merge-base --is-ancestor $G86AutomatedTestedHead HEAD
if ($LASTEXITCODE -ne 0) { throw "Automated-tested G8.6 head is not an ancestor of current checkout" }
& git -C $RootDir merge-base --is-ancestor $G86ManualObservedHead HEAD
if ($LASTEXITCODE -ne 0) { throw "Manual-observed G8.6 head is not an ancestor of current checkout" }

Write-Host "=== G8 FULL ACCEPTANCE: aggregate metadata scope ==="
$ChangedFilesText = Invoke-GitText @("diff", "--name-only", "$G86AcceptedMetadataCommit...HEAD")
$ChangedFiles = @($ChangedFilesText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-G8AggregateAllowedPath $_) })
if ($Unexpected.Count -gt 0) {
    throw "Files outside G8 aggregate-control allowlist changed after G8.6 acceptance:`n$($Unexpected -join "`n")"
}
& git -C $RootDir diff --check "$G86AcceptedMetadataCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed for G8 aggregate metadata" }
Write-Host "Aggregate-only post-G8.6 scope: PASS ($($ChangedFiles.Count) files)"

Write-Host "=== G8 FULL ACCEPTANCE: accepted chain ==="
$AcceptedRecords = @(
    "validation/g8-0-geomorphology-contracts-validation.json",
    "validation/g8-1-valley-incision-baseline-validation.json",
    "validation/g8-2-river-channel-incision-validation.json",
    "validation/g8-3-banks-floodplain-validation.json",
    "validation/g8-4-erosion-deposition-validation.json",
    "validation/g8-5-cross-cell-cross-lod-geomorphology-invariance-validation.json",
    "validation/g8-6-geomorphology-visual-lab-validation.json"
)
foreach ($RelativePath in $AcceptedRecords) {
    $AbsolutePath = Join-Path $RootDir $RelativePath
    if (-not (Test-Path -LiteralPath $AbsolutePath -PathType Leaf)) { throw "Missing G8 acceptance record: $RelativePath" }
    $Record = Get-Content -LiteralPath $AbsolutePath -Raw | ConvertFrom-Json
    Assert-Equal ([string]$Record.decision) "ACCEPTED" "$RelativePath is not ACCEPTED"
    Write-Host "$RelativePath : ACCEPTED"
}

$G86Manifest = Get-Content -LiteralPath (Join-Path $RootDir "config/procedural/g8-6-geomorphology-visual-lab.v1.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G86Manifest.status) "ACCEPTED" "G8.6 manifest is not ACCEPTED"
Assert-Equal ([string]$G86Manifest.acceptance.automated_tested_head) $G86AutomatedTestedHead "G8.6 automated head mismatch"
Assert-Equal ([string]$G86Manifest.acceptance.manual_graphical) "PASS" "G8.6 manual graphical evidence is not PASS"
Assert-Equal ([string]$G86Manifest.acceptance.manual_observed_head) $G86ManualObservedHead "G8.6 manual observed head mismatch"
Assert-Equal ([string]$G86Manifest.acceptance.manual_evidence.truth_hash) $ExpectedTruthHash "G8.6 graphical truth hash mismatch"
Assert-Equal ([string]$G86Manifest.acceptance.manual_evidence.canonical_samples) "PASS_561_STABLE" "G8.6 canonical sample evidence mismatch"

$G86Validation = Get-Content -LiteralPath (Join-Path $RootDir "validation/g8-6-geomorphology-visual-lab-validation.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G86Validation.manual_graphical_acceptance.status) "PASS" "G8.6 validation manual gate is not PASS"
Assert-Equal ([string]$G86Validation.manual_graphical_acceptance.observed_head) $G86ManualObservedHead "G8.6 validation observed head mismatch"
Assert-Equal ([string]$G86Validation.manual_graphical_acceptance.truth_hash) $ExpectedTruthHash "G8.6 validation truth hash mismatch"
Assert-Equal ([string]$G86Validation.manual_graphical_acceptance.canonical_samples) "561" "G8.6 validation canonical sample count mismatch"

Write-Host "=== G8 FULL ACCEPTANCE: executable G8.6 freshness ==="
$ExecutableGuardPaths = @(
    "scripts/simulation/procedural/geomorphology",
    "scripts/labs/procedural/g8_6_geomorphology_visual_lab.gd",
    "scripts/labs/procedural/g8_6_geomorphology_visual_lab_fix2.gd",
    "scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn",
    "tests/procedural/geomorphology/g8_6_geomorphology_visual_lab_acceptance.gd",
    "RUN_G8_6_GEOMORPHOLOGY_VISUAL_LAB_TESTS.ps1",
    "RUN_G8_6_AUTOMATED_ACCEPTANCE.ps1"
)
$ExecutableDrift = & git -C $RootDir diff --name-only "$G86AutomatedTestedHead..HEAD" -- @ExecutableGuardPaths
if ($LASTEXITCODE -ne 0) { throw "Unable to evaluate post-acceptance executable drift" }
$ExecutableDriftText = (($ExecutableDrift | Out-String).Trim())
if (-not [string]::IsNullOrWhiteSpace($ExecutableDriftText)) {
    throw "G8 executable/runtime changed after automated acceptance; revalidation required:`n$ExecutableDriftText"
}
Write-Host "Executable G8.6/runtime drift: NONE"

Write-Host "=== G8 FULL ACCEPTANCE: Project Control audit ==="
Invoke-PowerShellChild (Join-Path $RootDir "CONTROL_PROJECT.ps1") @("-NoFetch", "-NoFailOnRed")
if (-not (Test-Path -LiteralPath $ControlReportPath -PathType Leaf)) {
    throw "PC0 did not produce project-control-report.json"
}
$ControlReport = Get-Content -LiteralPath $ControlReportPath -Raw | ConvertFrom-Json
$GControl = @($ControlReport.programs | Where-Object { [string]$_.program -eq "G" }) | Select-Object -First 1
if ($null -eq $GControl) { throw "PC0 report does not contain G" }
if ([string]$GControl.health -eq "RED") {
    $FindingText = @($GControl.findings | ForEach-Object { "$($_.code): $($_.detail)" }) -join "`n"
    throw "PC0 blocks G8 Full Acceptance because G health is RED:`n$FindingText"
}
Write-Host "PC0 G health: $([string]$GControl.health) / NON_RED"

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G8 FULL ACCEPTANCE: fresh G8.6 focused/headless gate ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_G8_6_GEOMORPHOLOGY_VISUAL_LAB_TESTS.ps1") @("-GodotPath", $GodotPath)

    Write-Host "=== G8 FULL ACCEPTANCE: complete world/core regression ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1")
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    Remove-SafeWindowsProfileTransient -Phase "post-runtime"
}

Write-Host "=== G8 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) {
    throw "G8 Full Acceptance left tracked/untracked changes:`n$StatusAfter"
}
& git -C $RootDir diff --check "$G86AcceptedMetadataCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "Final G8 aggregate git diff --check failed" }

Write-Host "G8 FULL ACCEPTANCE: PASS"
Write-Host "Architecture revision: $ExpectedGlobalRevision"
Write-Host "Project Control revision: $ExpectedControlRevision"
Write-Host "G8.0-G8.6 accepted chain: PASS"
Write-Host "G8.6 manual graphical acceptance: PASS @ $G86ManualObservedHead"
Write-Host "G8.6 fresh focused/headless regression: PASS"
Write-Host "PC0 G health: NON_RED"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
Write-Host "NEXT: record G8 FULL ACCEPTED and FREEZE G8. G9 remains blocked on canonical R3/MAT0."
