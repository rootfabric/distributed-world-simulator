param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainRef = "origin/main"
$GlobalConfigPath = "config/architecture/global-program-roadmap.v1.json"
$GlobalRoadmapPath = "docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md"
$ExpectedGlobalRevision = "GLOBAL-P0-2026-08-10-R2"
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

function Test-G74AllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -in @(
        "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1",
        "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.sh",
        "RUN_G7_4_FULL_ACCEPTANCE.ps1",
        "START_G7_4_SEMANTIC_FIELD_LAB.ps1",
        "config/architecture/global-program-roadmap.v1.json",
        "config/procedural/g7-4-semantic-field-lab.v1.json",
        "config/procedural/g7-g13-p0-aligned-roadmap.v1.json",
        "docs/checkpoints/G7_4_SEMANTIC_FIELD_LAB_CANDIDATE_RU.md",
        "docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md",
        "docs/procedural/README_RU.md",
        "docs/procedural/STATUS_RU.md",
        "scenes/labs/procedural/g7_4_semantic_field_lab.tscn",
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

Write-Host "=== G7.4 FULL ACCEPTANCE: repository / P0 preflight ==="
Remove-SafeWindowsProfileTransient -Phase "stale-preflight"
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) {
    throw "G7.4 full acceptance requires a clean working tree:`n$StatusBefore"
}
foreach ($Ref in @($MainRef, $G73AcceptedCommit)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref/commit $Ref. Run git fetch origin first." }
}

$LocalGlobalConfigBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $GlobalConfigPath))
$MainGlobalConfigBlob = Invoke-GitText @("rev-parse", "$MainRef`:$GlobalConfigPath")
Assert-Equal $LocalGlobalConfigBlob $MainGlobalConfigBlob "G7.4 active global config differs from main"
$LocalGlobalRoadmapBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $GlobalRoadmapPath))
$MainGlobalRoadmapBlob = Invoke-GitText @("rev-parse", "$MainRef`:$GlobalRoadmapPath")
Assert-Equal $LocalGlobalRoadmapBlob $MainGlobalRoadmapBlob "G7.4 active global roadmap differs from main"

$GlobalConfig = Get-Content -LiteralPath (Join-Path $RootDir $GlobalConfigPath) -Raw | ConvertFrom-Json
Assert-Equal ([string]$GlobalConfig.global_revision) $ExpectedGlobalRevision "G7.4 active global revision is stale"
Assert-Equal ([string]$GlobalConfig.active_frontiers.world_generation.branch) "feature/g7-semantic-field-fabric" "G7.4 active frontier branch mismatch"
Assert-Equal ([string]$GlobalConfig.active_frontiers.world_generation.stage) "G7.4 Semantic Field Lab" "GLOBAL-P0 does not declare G7.4 active"
Write-Host "Global revision: $ExpectedGlobalRevision"
Write-Host "Active G7.4 GLOBAL-P0 main alignment: PASS"

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
    throw "G7.4 changed files outside visual-lab allowlist:`n$($Unexpected -join "`n")"
}
& git -C $RootDir diff --check "$G73AcceptedCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed for accepted G7.3...G7.4" }
Write-Host "G7.4 changed-file scope: PASS ($($ChangedFiles.Count) files)"

Assert-PowerShellParses (Join-Path $RootDir "RUN_G7_4_SEMANTIC_FIELD_LAB_TESTS.ps1")
Assert-PowerShellParses (Join-Path $RootDir "RUN_G7_4_FULL_ACCEPTANCE.ps1")
Assert-PowerShellParses (Join-Path $RootDir "START_G7_4_SEMANTIC_FIELD_LAB.ps1")
Write-Host "G7.4 PowerShell parse: PASS"

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
Write-Host "Global revision: $ExpectedGlobalRevision"
Write-Host "G7.3 ACCEPTED ancestor: PASS"
Write-Host "G7.4 visual-lab scope: PASS"
Write-Host "Five adapter-backed semantic fields: PASS"
Write-Host "Six vocabulary-only fields not faked: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
Write-Host "MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED"
