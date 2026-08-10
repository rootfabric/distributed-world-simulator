param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainRef = "origin/main"
$G6Ref = "origin/feature/g6-hydrology-fluid-surface-v0"
$ExpectedGlobalRevision = "GLOBAL-P0-2026-08-10-R2"
$ExpectedControlRevision = "PC0-2026-08-10-R1"
$GlobalRoadmapPath = "docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md"
$ProjectRegistryPath = "config/control/project-program-registry.v1.json"
$ProjectPolicyPath = "config/control/project-control-policy.v1.json"
$BranchPassportPath = "config/control/branches/feature__g7-semantic-field-fabric.v1.json"
$ControlReportPath = Join-Path $RootDir "artifacts/control/project-control-report.json"
$WindowsProfileTransientPath = Join-Path $RootDir "Microsoft"

$ValidationPaths = @(
    "validation/g7-0-semantic-field-contracts-validation.json",
    "validation/g7-1-upstream-semantic-field-adapters-validation.json",
    "validation/g7-2-composition-provenance-validation.json",
    "validation/g7-3-cross-cell-cross-lod-invariance-validation.json",
    "validation/g7-4-semantic-field-lab-validation.json"
)

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

function Test-G7AllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -eq "CONTROL_PROJECT.ps1") { return $true }
    if ($Path -match '^RUN_G7_[A-Z0-9_]+\.(ps1|sh)$') { return $true }
    if ($Path -eq "START_G7_4_SEMANTIC_FIELD_LAB.ps1") { return $true }
    if ($Path -match '^config/procedural/g7-') { return $true }
    if ($Path -match '^config/control/branches/feature__g7-semantic-field-fabric\.v1\.json$') { return $true }
    if ($Path -match '^config/architecture/global-program-roadmap\.v1\.json$') { return $true }
    if ($Path -match '^validation/g7-') { return $true }
    if ($Path -match '^docs/checkpoints/G7_') { return $true }
    if ($Path -match '^docs/procedural/(G7_|README_RU\.md$|STATUS_RU\.md$)') { return $true }
    if ($Path -eq $GlobalRoadmapPath) { return $true }
    if ($Path -match '^scripts/simulation/procedural/contracts/semantic_field_.*\.gd(\.uid)?$') { return $true }
    if ($Path -match '^scripts/simulation/procedural/semantic_fields/') { return $true }
    if ($Path -match '^tests/procedural/semantic_fields/g7_') { return $true }
    if ($Path -match '^scripts/labs/procedural/g7_') { return $true }
    if ($Path -match '^scenes/labs/procedural/g7_') { return $true }
    if ($Path -eq "scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd") { return $true }
    return $false
}

function Invoke-G7DiffCheck {
    & git -C $RootDir diff --check "$G6Ref...HEAD" -- . ":(exclude)$GlobalRoadmapPath"
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed for G6...G7 outside byte-matched canonical GLOBAL roadmap"
    }
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required for G7 full acceptance" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

Write-Host "=== G7 FULL ACCEPTANCE: repository / architecture / PC0 preflight ==="
Remove-SafeWindowsProfileTransient -Phase "stale-preflight"
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) { throw "G7 full acceptance requires a clean working tree:`n$StatusBefore" }
foreach ($Ref in @($MainRef, $G6Ref)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref $Ref. Run git fetch origin first." }
}

$ProjectRegistry = (Invoke-GitText @("show", "$MainRef`:$ProjectRegistryPath")) | ConvertFrom-Json
$ProjectPolicy = (Invoke-GitText @("show", "$MainRef`:$ProjectPolicyPath")) | ConvertFrom-Json
Assert-Equal ([string]$ProjectRegistry.control_plane_revision) $ExpectedControlRevision "main PC0 registry revision is unexpected"
Assert-Equal ([string]$ProjectPolicy.control_plane_revision) $ExpectedControlRevision "main PC0 policy revision is unexpected"
Assert-Equal ([string]$ProjectRegistry.architecture_revision) $ExpectedGlobalRevision "PC0 architecture revision mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.branch) "feature/g7-semantic-field-fabric" "PC0 G branch mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.current_stage) "G7 Full Acceptance" "PC0 does not declare G7 Full Acceptance"

$LocalGlobalRoadmapBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $GlobalRoadmapPath))
$MainGlobalRoadmapBlob = Invoke-GitText @("rev-parse", "$MainRef`:$GlobalRoadmapPath")
Assert-Equal $LocalGlobalRoadmapBlob $MainGlobalRoadmapBlob "G7 canonical GLOBAL roadmap differs from main"

$BranchPassport = Get-Content -LiteralPath (Join-Path $RootDir $BranchPassportPath) -Raw | ConvertFrom-Json
Assert-Equal ([string]$BranchPassport.control_plane_revision) $ExpectedControlRevision "G passport control revision mismatch"
Assert-Equal ([string]$BranchPassport.architecture_revision) $ExpectedGlobalRevision "G passport architecture revision mismatch"
Assert-Equal ([string]$BranchPassport.current_stage) "G7 Full Acceptance" "G passport stage mismatch"
Assert-Equal ([string]$BranchPassport.last_accepted_checkpoint) "G7.4 Semantic Field Lab" "G7.4 is not the accepted parent of G7 Full Acceptance"

& git -C $RootDir merge-base --is-ancestor $G6Ref HEAD
if ($LASTEXITCODE -ne 0) { throw "Current G7 head is not descended from accepted G6 lineage" }

Write-Host "=== G7 FULL ACCEPTANCE: accepted stage records ==="
foreach ($RelativePath in $ValidationPaths) {
    $Record = Get-Content -LiteralPath (Join-Path $RootDir $RelativePath) -Raw | ConvertFrom-Json
    if ([string]$Record.decision -ne "ACCEPTED") {
        throw "G7 full acceptance requires ACCEPTED decision: $RelativePath"
    }
    Write-Host "ACCEPTED: $RelativePath"
}
$G74Manifest = Get-Content -LiteralPath (Join-Path $RootDir "config/procedural/g7-4-semantic-field-lab.v1.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G74Manifest.status) "ACCEPTED" "G7.4 manifest is not ACCEPTED"
$G74Validation = Get-Content -LiteralPath (Join-Path $RootDir "validation/g7-4-semantic-field-lab-validation.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G74Validation.manual_graphical_acceptance.status) "PASS_BY_USER_OBSERVATION" "G7.4 graphical acceptance is incomplete"

Write-Host "=== G7 FULL ACCEPTANCE: G7 scope / hygiene ==="
$ChangedFilesText = Invoke-GitText @("diff", "--name-only", "$G6Ref...HEAD")
$ChangedFiles = @($ChangedFilesText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($ChangedFiles.Count -eq 0) { throw "G7 diff from G6 is empty" }
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-G7AllowedPath $_) })
if ($Unexpected.Count -gt 0) { throw "G7 changed files outside aggregate Semantic Field Fabric allowlist:`n$($Unexpected -join "`n")" }
Invoke-G7DiffCheck
Write-Host "G7 aggregate changed-file scope: PASS ($($ChangedFiles.Count) files)"
Write-Host "Canonical GLOBAL roadmap byte-match: PASS"

Write-Host "=== G7 FULL ACCEPTANCE: Project Control audit ==="
Invoke-PowerShellChild (Join-Path $RootDir "CONTROL_PROJECT.ps1") @("-NoFetch", "-NoFailOnRed")
if (-not (Test-Path -LiteralPath $ControlReportPath -PathType Leaf)) { throw "PC0 did not produce project-control-report.json" }
$ControlReport = Get-Content -LiteralPath $ControlReportPath -Raw | ConvertFrom-Json
$GControl = @($ControlReport.programs | Where-Object { [string]$_.program -eq "G" }) | Select-Object -First 1
if ($null -eq $GControl) { throw "PC0 report does not contain G" }
Assert-Equal ([string]$GControl.current_stage) "G7 Full Acceptance" "PC0 audited G stage mismatch"
if ([string]$GControl.health -eq "RED") {
    $FindingText = @($GControl.findings | ForEach-Object { "$($_.code): $($_.detail)" }) -join "`n"
    throw "PC0 blocks G7 full acceptance because G health is RED:`n$FindingText"
}
Write-Host "PC0 G health: $([string]$GControl.health)"
Write-Host "PC0 overall project health: $([string]$ControlReport.overall_health)"

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    Write-Host "=== G7 FULL ACCEPTANCE: aggregate semantic focused gate ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1") @("-GodotPath", $GodotPath)
    Write-Host "=== G7 FULL ACCEPTANCE: world/core regression ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1")
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    Remove-SafeWindowsProfileTransient -Phase "post-runtime"
}

Write-Host "=== G7 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) { throw "G7 full acceptance left tracked/untracked changes:`n$StatusAfter" }
Invoke-G7DiffCheck

Write-Host "G7 FULL ACCEPTANCE: PASS"
Write-Host "Architecture revision: $ExpectedGlobalRevision"
Write-Host "Project Control revision: $ExpectedControlRevision"
Write-Host "G7.0 ACCEPTED: PASS"
Write-Host "G7.1 ACCEPTED: PASS"
Write-Host "G7.2 ACCEPTED: PASS"
Write-Host "G7.3 ACCEPTED: PASS"
Write-Host "G7.4 ACCEPTED: PASS"
Write-Host "Semantic identity / provenance / cross-cell / presentation separation: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
Write-Host "NEXT: G8 GEOMORPHOLOGY"
