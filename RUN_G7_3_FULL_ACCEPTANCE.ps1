param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GlobalConfigPath = "config/architecture/global-program-roadmap.v1.json"
$G6Ref = "origin/feature/g6-hydrology-fluid-surface-v0"
$MainRef = "origin/main"
$G72AcceptedCommit = "68c4f90dbdac0e2d9968b4461207713f5661521b"
$WindowsProfileTransientPath = Join-Path $RootDir "Microsoft"
$WindowsProfileTransientExistedBefore = Test-Path -LiteralPath $WindowsProfileTransientPath

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

function Remove-NewWindowsProfileTransient {
    if ($WindowsProfileTransientExistedBefore -or -not (Test-Path -LiteralPath $WindowsProfileTransientPath)) {
        return
    }
    $TrackedEntries = (& git -C $RootDir ls-files -- "Microsoft" 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($TrackedEntries)) {
        Write-Warning "Refusing to clean Microsoft/ because tracked-state verification was not clean"
        return
    }
    try {
        Remove-Item -LiteralPath $WindowsProfileTransientPath -Recurse -Force -ErrorAction Stop
        Write-Host "Removed transient Windows profile directory: Microsoft/"
    }
    catch {
        Write-Warning "Could not remove transient Microsoft/ directory: $($_.Exception.Message)"
    }
}

function Test-G73AllowedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -in @(
        "RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1",
        "RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.sh",
        "RUN_G7_3_FULL_ACCEPTANCE.ps1",
        "config/procedural/g7-3-cross-cell-cross-lod-invariance.v1.json",
        "docs/checkpoints/G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_CANDIDATE_RU.md",
        "docs/procedural/README_RU.md",
        "docs/procedural/STATUS_RU.md",
        "validation/g7-3-cross-cell-cross-lod-invariance-validation.json"
    )) { return $true }
    if ($Path -match '^tests/procedural/semantic_fields/g7_3_cross_cell_cross_lod_invariance_acceptance\.gd(\.uid)?$') { return $true }
    return $false
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is required for G7.3 full acceptance" }
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
        (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
    )
    $GodotPath = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.1 double-precision editor was not found. Pass -GodotPath or set GODOT_BIN."
}

Write-Host "=== G7.3 FULL ACCEPTANCE: repository / P0 preflight ==="
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) { throw "G7.3 full acceptance requires a clean working tree:`n$StatusBefore" }
foreach ($Ref in @($MainRef, $G6Ref, $G72AcceptedCommit)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing required ref/commit $Ref. Run git fetch origin first." }
}

$LocalGlobalBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $GlobalConfigPath))
$MainGlobalBlob = Invoke-GitText @("rev-parse", "$MainRef`:$GlobalConfigPath")
$G6GlobalBlob = Invoke-GitText @("rev-parse", "$G6Ref`:$GlobalConfigPath")
Assert-Equal $LocalGlobalBlob $MainGlobalBlob "G7.3 global config differs from main"
Assert-Equal $LocalGlobalBlob $G6GlobalBlob "G7.3 global config differs from G6"
$GlobalConfig = Get-Content -LiteralPath (Join-Path $RootDir $GlobalConfigPath) -Raw | ConvertFrom-Json
$GlobalRevision = [string]$GlobalConfig.global_revision
if ([string]::IsNullOrWhiteSpace($GlobalRevision)) { throw "Global program revision is missing" }
Write-Host "Global revision: $GlobalRevision"

& git -C $RootDir merge-base --is-ancestor $G6Ref HEAD
if ($LASTEXITCODE -ne 0) { throw "Current G7.3 head is not synchronized on top of current G6" }
& git -C $RootDir merge-base --is-ancestor $G72AcceptedCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "G7.2 accepted checkpoint is not an ancestor of current G7.3 head" }
$G72Record = Get-Content -LiteralPath (Join-Path $RootDir "validation/g7-2-composition-provenance-validation.json") -Raw | ConvertFrom-Json
if ([string]$G72Record.decision -ne "ACCEPTED") { throw "G7.2 acceptance record is missing or stale" }

Write-Host "=== G7.3 FULL ACCEPTANCE: scope / hygiene ==="
$ChangedFilesText = Invoke-GitText @("diff", "--name-only", "$G72AcceptedCommit...HEAD")
$ChangedFiles = @($ChangedFilesText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($ChangedFiles.Count -eq 0) { throw "G7.3 diff is empty" }
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-G73AllowedPath $_) })
if ($Unexpected.Count -gt 0) { throw "G7.3 changed files outside invariance allowlist:`n$($Unexpected -join "`n")" }
& git -C $RootDir diff --check "$G72AcceptedCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed for accepted G7.2...G7.3" }
Write-Host "G7.3 changed-file scope: PASS ($($ChangedFiles.Count) files)"

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    Write-Host "=== G7.3 FULL ACCEPTANCE: focused invariance ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1") @("-GodotPath", $GodotPath)
    Write-Host "=== G7.3 FULL ACCEPTANCE: full world/core regression ==="
    Invoke-PowerShellChild (Join-Path $RootDir "RUN_WORLD_REGRESSION_TESTS.ps1")
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    Remove-NewWindowsProfileTransient
}

Write-Host "=== G7.3 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) { throw "G7.3 full acceptance left tracked/untracked changes:`n$StatusAfter" }
& git -C $RootDir diff --check "$G72AcceptedCommit...HEAD"
if ($LASTEXITCODE -ne 0) { throw "Final git diff --check failed" }

Write-Host "G7.3 FULL ACCEPTANCE: PASS"
Write-Host "Global revision: $GlobalRevision"
Write-Host "G7.2 ACCEPTED ancestor: PASS"
Write-Host "G7.3 invariance scope: PASS"
Write-Host "Cross-cell / cross-LOD semantic invariance: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
