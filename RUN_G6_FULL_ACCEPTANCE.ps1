param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GlobalConfigPath = "config/architecture/global-program-roadmap.v1.json"
$G5Ref = "origin/feature/g5-world-feature-graph"
$MainRef = "origin/main"
$Mw10RepositoryPath = "scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd"
$Mw10RetryTestPath = "tests/matter/transactions/test_mw10_lock_release_retry.gd"
$ExpectedMw10RepositoryBlob = "a25b7d8c358410e60e1bb7db9d3f99333a305a63"
$ExpectedMw10RetryTestBlob = "afab0c98de45c34dcf6c923d622c84835d428fa5"

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

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required for G6 full acceptance"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
        (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
    )
    $GodotPath = $Candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -Unique |
        Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.1 double-precision editor was not found. Pass -GodotPath or set GODOT_BIN."
}

Write-Host "=== G6 FULL ACCEPTANCE: repository / sync preflight ==="
$StatusBefore = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusBefore)) {
    throw "G6 full acceptance requires a clean working tree before runtime validation:`n$StatusBefore"
}

foreach ($Ref in @($MainRef, $G5Ref)) {
    & git -C $RootDir rev-parse --verify --quiet $Ref | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Missing required ref $Ref. Run git fetch origin before G6 full acceptance."
    }
}

$LocalGlobalBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $GlobalConfigPath))
$MainGlobalBlob = Invoke-GitText @("rev-parse", "$MainRef`:$GlobalConfigPath")
$G5GlobalBlob = Invoke-GitText @("rev-parse", "$G5Ref`:$GlobalConfigPath")
Assert-Equal $LocalGlobalBlob $MainGlobalBlob "G6 global config differs from main"
Assert-Equal $LocalGlobalBlob $G5GlobalBlob "G6 global config differs from G5 shared baseline"

$GlobalConfig = Get-Content -LiteralPath (Join-Path $RootDir $GlobalConfigPath) -Raw | ConvertFrom-Json
$GlobalRevision = [string]$GlobalConfig.global_revision
if ([string]::IsNullOrWhiteSpace($GlobalRevision)) {
    throw "Global program revision is missing"
}
Write-Host "Global revision: $GlobalRevision"
Write-Host "Global config blob: $LocalGlobalBlob"

& git -C $RootDir merge-base --is-ancestor $G5Ref HEAD
if ($LASTEXITCODE -ne 0) {
    throw "Current G6 head is not synchronized on top of the current G5 baseline"
}

Write-Host "=== G6 FULL ACCEPTANCE: shared MW10 baseline ==="
$G5Mw10RepositoryBlob = Invoke-GitText @("rev-parse", "$G5Ref`:$Mw10RepositoryPath")
Assert-Equal $G5Mw10RepositoryBlob $ExpectedMw10RepositoryBlob "G5 does not yet contain the independently accepted MW10 atomic-lock repository blob. Integrate PR #43 into G5 first."
$G5Mw10RetryBlob = Invoke-GitText @("rev-parse", "$G5Ref`:$Mw10RetryTestPath")
Assert-Equal $G5Mw10RetryBlob $ExpectedMw10RetryTestBlob "G5 does not yet contain the independently accepted MW10 lock-release retry test blob. Integrate PR #43 into G5 first."

$LocalMw10RepositoryBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $Mw10RepositoryPath))
$LocalMw10RetryBlob = Invoke-GitText @("hash-object", (Join-Path $RootDir $Mw10RetryTestPath))
Assert-Equal $LocalMw10RepositoryBlob $ExpectedMw10RepositoryBlob "G6 has not been resynchronized with the accepted MW10 repository fix"
Assert-Equal $LocalMw10RetryBlob $ExpectedMw10RetryTestBlob "G6 has not been resynchronized with the accepted MW10 retry test"

Write-Host "=== G6 FULL ACCEPTANCE: procedural diff hygiene ==="
& git -C $RootDir diff --check "$G5Ref...HEAD"
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed for G5...G6"
}

$ManualRecordPath = Join-Path $RootDir "validation/g6-4-casual-visual-river-lab-validation.json"
$ManualRecord = Get-Content -LiteralPath $ManualRecordPath -Raw | ConvertFrom-Json
if ([string]$ManualRecord.decision -ne "FIX4_MANUAL_PASS_AUTOMATED_RERUN_REQUIRED") {
    throw "G6.4 Fix4 manual graphical PASS record is missing or stale"
}

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
$HadBreakpointRuntimeDisabled = Test-Path Env:\BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpointRuntimeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:GODOT_BIN = $GodotPath
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    Write-Host "=== G6 FULL ACCEPTANCE: G6.4 Fix4 closes G6.0-G6.4 chain ==="
    & "$RootDir\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1" -GodotPath $GodotPath
    if (-not $?) {
        throw "G6.0-G6.4 focused chain failed"
    }

    Write-Host "=== G6 FULL ACCEPTANCE: MW10 atomic-lock fault injection ==="
    & $GodotPath --headless --path $RootDir --script "res://tests/matter/transactions/test_mw10_lock_release_retry.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "MW10 atomic-lock release retry regression failed"
    }

    Write-Host "=== G6 FULL ACCEPTANCE: full world/core regression ==="
    & "$RootDir\RUN_WORLD_REGRESSION_TESTS.ps1"
    if (-not $?) {
        throw "World/core regression failed"
    }
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
    if ($HadBreakpointRuntimeDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointRuntimeDisabled }
    else { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}

Write-Host "=== G6 FULL ACCEPTANCE: final hygiene ==="
$StatusAfter = Invoke-GitText @("status", "--porcelain")
if (-not [string]::IsNullOrWhiteSpace($StatusAfter)) {
    throw "G6 full acceptance left tracked/untracked repository changes:`n$StatusAfter"
}
& git -C $RootDir diff --check "$G5Ref...HEAD"
if ($LASTEXITCODE -ne 0) {
    throw "Final git diff --check failed"
}

Write-Host "G6 FULL ACCEPTANCE: PASS"
Write-Host "Global revision: $GlobalRevision"
Write-Host "G5 shared MW10 atomic-lock baseline: PASS"
Write-Host "G6.0-G6.4 focused chain: PASS"
Write-Host "MW10 lock-release retry: PASS"
Write-Host "World/core regression: PASS"
Write-Host "Working tree: CLEAN"
