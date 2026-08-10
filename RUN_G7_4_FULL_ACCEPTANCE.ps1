param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainRef = "origin/main"
$GlobalConfigPath = "config/architecture/global-program-roadmap.v1.json"
$ExpectedGlobalRevision = "GLOBAL-P0-2026-08-10-R2"
$ExpectedControlRevision = "PC0-2026-08-10-R1"
$ProjectRegistryPath = "config/control/project-program-registry.v1.json"
$ProjectPolicyPath = "config/control/project-control-policy.v1.json"
$BranchPassportPath = "config/control/branches/feature__g7-semantic-field-fabric.v1.json"
$ControlReportPath = Join-Path $RootDir "artifacts/control/project-control-report.json"
$G73AcceptedCommit = "1a2808a2e03c565c9a52fc467c51398d43fcf3e9"
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
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Actual -ne $Expected) {
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
        throw "Could not resolve current PowerShell executable for isolated child runners"
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
        Write-Warning "Refusing to clean Microsoft/ during $Phase because it is not proven to be purely untracked transient content"
        return
    }
    Remove-Item -LiteralPath $WindowsProfileTransientPath -Recurse -Force -ErrorAction Stop
    Write-Host "Removed $Phase Windows profile transient directory: Microsoft/"
}

function Assert-PowerShellParses {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$Errors
    ) | Out-Null
    if ($Errors.Count -gt 0) {
        $Errors | Format-List | Out-Host
        throw "PowerShell parse failed: $Path"
    }
}

function Assert-AsciiFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Bytes = [IO.File]::ReadAllBytes($Path)
    foreach ($Byte in $Bytes) {
        if ($Byte -gt 127) {
            throw "Windows PowerShell compatibility requires ASCII-only G7.4 runner/launcher: $Path"
        }
    }
}

function Test-G74AllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -in @(
        "CONTROL_PROJECT.ps1",
        "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1",
        "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.sh",
        "RUN_G7_4_FULL_ACCEPTANCE.ps1",
        "START_G7_4_SEMANTIC_FIELD_LAB.ps1",
        "config/architecture/global-program-roadmap.v1.json",
        "config/control/branches/feature__g7-semantic-field-fabric.v1.json",
        "config/procedural/g7-4-semantic-field-lab.v1.json",
        "config/procedural/g7-g13-p0-aligned-roadmap.v1.json",
        "docs/checkpoints/G7_4_SEMANTIC_FIELD_LAB_CANDIDATE_RU.md",
        "docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md",
        "docs/procedural/README_RU.md",
        "docs/procedural/STATUS_RU.md",
        "scenes/labs/procedural/g7_4_semantic_field_lab.tscn",
        "scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd",
        "tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance.gd",
        "validation/g7-4-semantic-field-lab-validation.json"
    )) { return $true }
    if ($Path -match '^scripts/labs/procedural/g7_4_semantic_field_lab\.gd(\.uid)?$') { return $true }
    if ($Path -match '^tests/procedural/semantic_fields/g7_4_semantic_field_lab_acceptance\.gd(\.uid)?$') { return $true }
    return $false
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required for G7.4 full acceptance" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

Write-Host "=== G7.4 FULL ACCEPTANCE: repository / architecture / PC0 preflight ==="
Remove-SafeWindowsProfileTransient -Phase "stale-preflight"
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) {
    throw "G7.4 full acceptance requires a clean working tree:`n$StatusBefore"
}
foreach ($Ref in @($MainRef, $G73AcceptedCommit)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref/commit $Ref. Run git fetch origin first." }
}

$MainGlobalConfig = (Invoke-GitText @("show", "$MainRef`:$GlobalConfigPath")) | ConvertFrom-Json
$LocalGlobalConfig = Get-Content -LiteralPath (Join-Path $RootDir $GlobalConfigPath) -Raw | ConvertFrom-Json
Assert-Equal ([string]$MainGlobalConfig.global_revision) $ExpectedGlobalRevision "main GLOBAL-P0 revision is unexpected"
Assert-Equal ([string]$LocalGlobalConfig.global_revision) $ExpectedGlobalRevision "G7.4 local architecture revision is stale"

$ProjectRegistry = (Invoke-GitText @("show", "$MainRef`:$ProjectRegistryPath")) | ConvertFrom-Json
$ProjectPolicy = (Invoke-GitText @("show", "$MainRef`:$ProjectPolicyPath")) | ConvertFrom-Json
Assert-Equal ([string]$ProjectRegistry.control_plane_revision) $ExpectedControlRevision "main PC0 registry revision is unexpected"
Assert-Equal ([string]$ProjectPolicy.control_plane_revision) $ExpectedControlRevision "main PC0 policy revision is unexpected"
Assert-Equal ([string]$ProjectRegistry.architecture_revision) $ExpectedGlobalRevision "PC0 registry architecture revision mismatch"
Assert-Equal ([string]$ProjectPolicy.architecture_revision) $ExpectedGlobalRevision "PC0 policy architecture revision mismatch"
Assert-Equal ([string]$ProjectPolicy.operational_frontier_source) $ProjectRegistryPath "PC0 operational frontier source mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.branch) "feature/g7-semantic-field-fabric" "PC0 G frontier branch mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.current_stage) "G7.4 Semantic Field Lab" "PC0 does not declare G7.4 as the operational G frontier"

$BranchPassport = Get-Content -LiteralPath (Join-Path $RootDir $BranchPassportPath) -Raw | ConvertFrom-Json
Assert-Equal ([string]$BranchPassport.control_plane_revision) $ExpectedControlRevision "G branch passport PC0 revision mismatch"
Assert-Equal ([string]$BranchPassport.architecture_revision) $ExpectedGlobalRevision "G branch passport architecture revision mismatch"
Assert-Equal ([string]$BranchPassport.branch) "feature/g7-semantic-field-fabric" "G branch passport branch mismatch"
Assert-Equal ([string]$BranchPassport.program) "G" "G branch passport program mismatch"
Assert-Equal ([string]$BranchPassport.current_stage) "G7.4 Semantic Field Lab" "G branch passport stage mismatch"
Write-Host "Architecture revision: $ExpectedGlobalRevision"
Write-Host "Project Control revision: $ExpectedControlRevision"
Write-Host "PC0 operational G frontier: G7.4 Semantic Field Lab"
Write-Host "Legacy GLOBAL-P0 active_frontiers: advisory only (not used as operational gate)"

& git -C $RootDir merge-base --is-ancestor $G73AcceptedCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "G7.3 accepted checkpoint is not an ancestor of current G7.4 head" }
$G73Record = Get-Content -LiteralPath (Join-Path $RootDir "validation/g7-3-cross-cell-cross-lod-invariance-validation.json") -Raw | ConvertFrom-Json
if ([string]$G73Record.decision -ne "ACCEPTED") { throw "G7.3 acceptance record is missing or stale" }

Write-Host "=== G7.4 FULL ACCEPTANCE: scope / hygiene ==="
$ChangedFilesText = Invoke-GitText @("diff", "--name-only", "$G73AcceptedCommit...HEAD")
$ChangedFiles = @($ChangedFilesText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($ChangedFiles.Count -eq 0) { throw "G7.4 diff is empty" }
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-G74AllowedPath $_) })
if ($Unexpected.Count -gt 0) {
    throw "G7.4 changed files outside visual-lab/control/shared-M5-fix allowlist:`n$($Unexpected -join "`n")"
}
& git -C $RootDir diff --check "$G73AcceptedCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed for accepted G7.3...G7.4" }
Write-Host "G7.4 changed-file scope: PASS ($($ChangedFiles.Count) files)"

foreach ($PowerShellPath in @(
    (Join-Path $RootDir "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1"),
    (Join-Path $RootDir "RUN_G7_4_FULL_ACCEPTANCE.ps1"),
    (Join-Path $RootDir "START_G7_4_SEMANTIC_FIELD_LAB.ps1")
)) {
    Assert-AsciiFile $PowerShellPath
    Assert-PowerShellParses $PowerShellPath
}
Write-Host "G7.4 Windows PowerShell ASCII + parse: PASS"

Write-Host "=== G7.4 FULL ACCEPTANCE: Project Control audit ==="
Invoke-PowerShellChild (Join-Path $RootDir "CONTROL_PROJECT.ps1") @("-NoFetch", "-NoFailOnRed")
if (-not (Test-Path -LiteralPath $ControlReportPath -PathType Leaf)) {
    throw "PC0 did not produce project-control-report.json"
}
$ControlReport = Get-Content -LiteralPath $ControlReportPath -Raw | ConvertFrom-Json
$GControl = @($ControlReport.programs | Where-Object { [string]$_.program -eq "G" }) | Select-Object -First 1
if ($null -eq $GControl) { throw "PC0 report does not contain G program" }
Assert-Equal ([string]$GControl.branch) "feature/g7-semantic-field-fabric" "PC0 audited G branch mismatch"
Assert-Equal ([string]$GControl.current_stage) "G7.4 Semantic Field Lab" "PC0 audited G stage mismatch"
if ([string]$GControl.health -eq "RED") {
    $FindingText = @($GControl.findings | ForEach-Object { "$($_.code): $($_.detail)" }) -join "`n"
    throw "PC0 blocks G7.4 acceptance because G health is RED:`n$FindingText"
}
Write-Host "PC0 G health: $([string]$GControl.health)"
Write-Host "PC0 overall project health: $([string]$ControlReport.overall_health) (unrelated program RED does not block G when G itself is not RED)"

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    Write-Host "=== G7.4 FULL ACCEPTANCE: focused semantic lab ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1") @("-GodotPath", $GodotPath)
    Write-Host "=== G7.4 FULL ACCEPTANCE: world/core regression ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1")
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    Remove-SafeWindowsProfileTransient -Phase "post-runtime"
}

Write-Host "=== G7.4 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) {
    throw "G7.4 full acceptance left tracked/untracked changes:`n$StatusAfter"
}
& git -C $RootDir diff --check "$G73AcceptedCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "Final G7.4 git diff --check failed" }

Write-Host "G7.4 AUTOMATED ACCEPTANCE: PASS"
Write-Host "Architecture revision: $ExpectedGlobalRevision"
Write-Host "Project Control revision: $ExpectedControlRevision"
Write-Host "PC0 operational G frontier: PASS"
Write-Host "PC0 G health is not RED: PASS"
Write-Host "G7.3 ACCEPTED ancestor: PASS"
Write-Host "G7.4 visual-lab scope: PASS"
Write-Host "Five adapter-backed semantic fields: PASS"
Write-Host "Six vocabulary-only fields not faked: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
Write-Host "MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED"
