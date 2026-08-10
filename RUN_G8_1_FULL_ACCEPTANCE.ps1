param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainRef = "origin/main"
$G80AcceptedMetadataCommit = "5061d0ce77a1c08b2ea730dcb768810065df90c5"
$ExpectedGlobalRevision = "GLOBAL-P0-2026-08-10-R2"
$ExpectedControlRevision = "PC0-2026-08-10-R1"
$ProjectRegistryPath = "config/control/project-program-registry.v1.json"
$ProjectPolicyPath = "config/control/project-control-policy.v1.json"
$BranchPassportPath = "config/control/branches/feature__g8-geomorphology.v1.json"
$ControlReportPath = Join-Path $RootDir "artifacts/control/project-control-report.json"
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

function Test-G81AllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -in @(
        "RUN_G8_1_VALLEY_INCISION_TESTS.ps1",
        "RUN_G8_1_FULL_ACCEPTANCE.ps1",
        "config/control/branches/feature__g8-geomorphology.v1.json",
        "config/procedural/g7-g13-p0-aligned-roadmap.v1.json",
        "config/procedural/g8-1-valley-incision-baseline.v1.json",
        "docs/checkpoints/G8_1_VALLEY_INCISION_BASELINE_CANDIDATE_RU.md",
        "validation/g8-1-valley-incision-baseline-validation.json",
        "tests/procedural/geomorphology/g8_0_geomorphology_contracts_acceptance.gd"
    )) { return $true }
    if ($Path -match '^scripts/simulation/procedural/geomorphology/valley_incision_baseline_v1\.gd(\.uid)?$') { return $true }
    if ($Path -match '^tests/procedural/geomorphology/g8_1_valley_incision_acceptance\.gd(\.uid)?$') { return $true }
    return $false
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required for G8.1 full acceptance" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }

Write-Host "=== G8.1 FULL ACCEPTANCE: repository / architecture / PC0 preflight ==="
Remove-SafeWindowsProfileTransient -Phase "stale-preflight"
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) { throw "G8.1 full acceptance requires a clean working tree:`n$StatusBefore" }
foreach ($Ref in @($MainRef, $G80AcceptedMetadataCommit)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref/commit $Ref. Run git fetch origin first." }
}

$ProjectRegistry = (Invoke-GitText @("show", "$MainRef`:$ProjectRegistryPath")) | ConvertFrom-Json
$ProjectPolicy = (Invoke-GitText @("show", "$MainRef`:$ProjectPolicyPath")) | ConvertFrom-Json
Assert-Equal ([string]$ProjectRegistry.control_plane_revision) $ExpectedControlRevision "main PC0 registry revision is unexpected"
Assert-Equal ([string]$ProjectPolicy.control_plane_revision) $ExpectedControlRevision "main PC0 policy revision is unexpected"
Assert-Equal ([string]$ProjectRegistry.architecture_revision) $ExpectedGlobalRevision "PC0 architecture revision mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.branch) "feature/g8-geomorphology" "PC0 G branch mismatch"
Assert-Equal ([string]$ProjectRegistry.programs.G.current_stage) "G8.1 Valley Incision Baseline" "PC0 does not declare G8.1"

$BranchPassport = Get-Content -LiteralPath (Join-Path $RootDir $BranchPassportPath) -Raw | ConvertFrom-Json
Assert-Equal ([string]$BranchPassport.control_plane_revision) $ExpectedControlRevision "G8 passport control revision mismatch"
Assert-Equal ([string]$BranchPassport.architecture_revision) $ExpectedGlobalRevision "G8 passport architecture revision mismatch"
Assert-Equal ([string]$BranchPassport.current_stage) "G8.1 Valley Incision Baseline" "G8 passport stage mismatch"
Assert-Equal ([string]$BranchPassport.last_accepted_checkpoint) "G8.0 Geomorphology Contracts" "G8.0 is not the accepted G8.1 parent"

& git -C $RootDir merge-base --is-ancestor $G80AcceptedMetadataCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "Accepted G8.0 metadata head is not an ancestor of G8.1" }
$G80Record = Get-Content -LiteralPath (Join-Path $RootDir "validation/g8-0-geomorphology-contracts-validation.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G80Record.decision) "ACCEPTED" "G8.0 validation record is not ACCEPTED"
$G81Manifest = Get-Content -LiteralPath (Join-Path $RootDir "config/procedural/g8-1-valley-incision-baseline.v1.json") -Raw | ConvertFrom-Json
Assert-Equal ([string]$G81Manifest.status) "IMPLEMENTED_CANDIDATE" "G8.1 manifest is not an implemented candidate"

Write-Host "=== G8.1 FULL ACCEPTANCE: scope / hygiene ==="
$ChangedFilesText = Invoke-GitText @("diff", "--name-only", "$G80AcceptedMetadataCommit...HEAD")
$ChangedFiles = @($ChangedFilesText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($ChangedFiles.Count -eq 0) { throw "G8.1 diff is empty" }
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-G81AllowedPath $_) })
if ($Unexpected.Count -gt 0) { throw "G8.1 changed files outside valley/control allowlist:`n$($Unexpected -join "`n")" }
& git -C $RootDir diff --check "$G80AcceptedMetadataCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed for accepted G8.0...G8.1" }
Write-Host "G8.1 changed-file scope: PASS ($($ChangedFiles.Count) files)"

Write-Host "=== G8.1 FULL ACCEPTANCE: Project Control audit ==="
Invoke-PowerShellChild (Join-Path $RootDir "CONTROL_PROJECT.ps1") @("-NoFetch", "-NoFailOnRed")
if (-not (Test-Path -LiteralPath $ControlReportPath -PathType Leaf)) { throw "PC0 did not produce project-control-report.json" }
$ControlReport = Get-Content -LiteralPath $ControlReportPath -Raw | ConvertFrom-Json
$GControl = @($ControlReport.programs | Where-Object { [string]$_.program -eq "G" }) | Select-Object -First 1
if ($null -eq $GControl) { throw "PC0 report does not contain G" }
Assert-Equal ([string]$GControl.branch) "feature/g8-geomorphology" "PC0 audited G8 branch mismatch"
Assert-Equal ([string]$GControl.current_stage) "G8.1 Valley Incision Baseline" "PC0 audited G8.1 stage mismatch"
if ([string]$GControl.health -eq "RED") {
    $FindingText = @($GControl.findings | ForEach-Object { "$($_.code): $($_.detail)" }) -join "`n"
    throw "PC0 blocks G8.1 acceptance because G health is RED:`n$FindingText"
}
Write-Host "PC0 G health: $([string]$GControl.health)"

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    Write-Host "=== G8.1 FULL ACCEPTANCE: focused valley baseline ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_G8_1_VALLEY_INCISION_TESTS.ps1") @("-GodotPath", $GodotPath)
    Write-Host "=== G8.1 FULL ACCEPTANCE: world/core regression ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1")
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    Remove-SafeWindowsProfileTransient -Phase "post-runtime"
}

Write-Host "=== G8.1 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) { throw "G8.1 full acceptance left tracked/untracked changes:`n$StatusAfter" }
& git -C $RootDir diff --check "$G80AcceptedMetadataCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "Final G8.1 git diff --check failed" }

Write-Host "G8.1 FULL ACCEPTANCE: PASS"
Write-Host "Architecture revision: $ExpectedGlobalRevision"
Write-Host "Project Control revision: $ExpectedControlRevision"
Write-Host "G8.0 parent ACCEPTED: PASS"
Write-Host "G8.1 valley incision baseline: PASS"
Write-Host "Geomorphology ownership boundary: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
Write-Host "NEXT: G8.2 RIVER CHANNEL INCISION"
