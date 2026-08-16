[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(2, 1000)][int]$RequireHandoffs = 10,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$Runner = Join-Path $PSScriptRoot "RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "SM0 controlled WAN matrix runner is missing: $Runner"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$MatrixRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalLab\matrix"
$RecoveryRootBase = Join-Path $LocalAppData "DistributedWorldSimulator\SM0P4Recovery"
$RecoveryRunId = "wan-{0}-{1}-{2}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $PID, ([guid]::NewGuid().ToString("N").Substring(0, 8))
$RecoveryRoot = Join-Path $RecoveryRootBase $RecoveryRunId
if (-not $Stop) {
    New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
}
$BeforeMatrixDirs = @{}
if (Test-Path -LiteralPath $MatrixRoot -PathType Container) {
    foreach ($Dir in Get-ChildItem -LiteralPath $MatrixRoot -Directory -ErrorAction SilentlyContinue) {
        $BeforeMatrixDirs[$Dir.FullName] = $true
    }
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$HadP4Recovery = Test-Path Env:SM0_P4_RECOVERY_DIR
$PreviousP4Recovery = $env:SM0_P4_RECOVERY_DIR
$HadAutoQuit = Test-Path Env:SM0_P4_MATRIX_AUTO_QUIT_HANDOFFS
$PreviousAutoQuit = $env:SM0_P4_MATRIX_AUTO_QUIT_HANDOFFS
$ExitCode = 1
try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    $env:SM0_P4_RECOVERY_DIR = $RecoveryRoot
    if (-not $Stop) {
        $env:SM0_P4_MATRIX_AUTO_QUIT_HANDOFFS = [string]$RequireHandoffs
    }
    Write-Host "[SM0-P4] Prewarmed fast handoff ENABLED for WAN matrix." -ForegroundColor Cyan
    if (-not $Stop) {
        Write-Host "[SM0-P4] Durable protocol recovery root: $RecoveryRoot" -ForegroundColor DarkCyan
        Write-Host "[SM0-P4] Each WAN profile will close automatically after $RequireHandoffs confirmed handoffs." -ForegroundColor Cyan
        Write-Host "[SM0-P4] Keep crossing with A/D until the window closes by itself; do not close it manually." -ForegroundColor Cyan
    }
    & $Runner @PSBoundParameters
    $ExitCode = $LASTEXITCODE
}
finally {
    if ($HadP4) { $env:SM0_P4_FAST_HANDOFF = $PreviousP4 }
    else { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue }
    if ($HadP4Recovery) { $env:SM0_P4_RECOVERY_DIR = $PreviousP4Recovery }
    else { Remove-Item Env:SM0_P4_RECOVERY_DIR -ErrorAction SilentlyContinue }
    if ($HadAutoQuit) { $env:SM0_P4_MATRIX_AUTO_QUIT_HANDOFFS = $PreviousAutoQuit }
    else { Remove-Item Env:SM0_P4_MATRIX_AUTO_QUIT_HANDOFFS -ErrorAction SilentlyContinue }
}

if ($ExitCode -ne 0 -or $Stop) {
    exit $ExitCode
}

$NewMatrixDirs = @(
    Get-ChildItem -LiteralPath $MatrixRoot -Directory -ErrorAction Stop |
        Where-Object { -not $BeforeMatrixDirs.ContainsKey($_.FullName) } |
        Sort-Object LastWriteTime -Descending
)
if ($NewMatrixDirs.Count -lt 1) {
    throw "SM0-P4 could not locate the newly-created WAN matrix directory."
}
$MatrixDir = $NewMatrixDirs[0].FullName
$MatrixSummaryPath = Join-Path $MatrixDir "controlled-network-latency-matrix-summary.json"
if (-not (Test-Path -LiteralPath $MatrixSummaryPath -PathType Leaf)) {
    throw "SM0-P4 matrix summary is missing: $MatrixSummaryPath"
}
$Matrix = Get-Content -LiteralPath $MatrixSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop

function Get-P4FastTransferIds([string]$LogPath) {
    $Ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Line in Get-Content -LiteralPath $LogPath -ErrorAction Stop) {
        if (-not $Line.Contains('"event":"SM0_P4_FAST_COMMIT_ACCEPTED"')) { continue }
        $Brace = $Line.IndexOf('{')
        if ($Brace -lt 0) { continue }
        $Event = $Line.Substring($Brace) | ConvertFrom-Json -ErrorAction Stop
        $TransferId = [string]$Event.transfer_id
        if (-not [string]::IsNullOrWhiteSpace($TransferId)) { [void]$Ids.Add($TransferId) }
    }
    return $Ids
}

$EvidenceProfiles = [System.Collections.Generic.List[object]]::new()
foreach ($Profile in @($Matrix.profiles)) {
    $ChildSummaryPath = [string]$Profile.child_summary
    if (-not (Test-Path -LiteralPath $ChildSummaryPath -PathType Leaf)) {
        throw "SM0-P4 child summary missing for $($Profile.label): $ChildSummaryPath"
    }
    $Child = Get-Content -LiteralPath $ChildSummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $ServerALog = [string]$Child.server_a_log
    $ServerBLog = [string]$Child.server_b_log
    foreach ($Path in @($ServerALog, $ServerBLog)) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "SM0-P4 server evidence log missing for $($Profile.label): $Path"
        }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P4_MODE"' -Quiet -ErrorAction SilentlyContinue)) {
            throw "SM0-P4 mode marker missing for $($Profile.label): $Path"
        }
        if (-not (Select-String -LiteralPath $Path -SimpleMatch '"event":"SM0_P4_HARDENING_READY"' -Quiet -ErrorAction SilentlyContinue)) {
            throw "SM0-P4 hardening marker missing for $($Profile.label): $Path"
        }
    }

    $FastA = Get-P4FastTransferIds $ServerALog
    $FastB = Get-P4FastTransferIds $ServerBLog
    $FastIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Id in $FastA) { [void]$FastIds.Add($Id) }
    foreach ($Id in $FastB) { [void]$FastIds.Add($Id) }

    $MeasuredIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($Sample in @($Child.samples)) {
        $TransferId = [string]$Sample.transfer_id
        if (-not [string]::IsNullOrWhiteSpace($TransferId)) { [void]$MeasuredIds.Add($TransferId) }
    }
    if ($MeasuredIds.Count -lt $RequireHandoffs) {
        throw "SM0-P4 $($Profile.label) has only $($MeasuredIds.Count) measured transfer ids; expected at least $RequireHandoffs."
    }
    $MissingFast = [System.Collections.Generic.List[string]]::new()
    foreach ($TransferId in $MeasuredIds) {
        if (-not $FastIds.Contains($TransferId)) { $MissingFast.Add($TransferId) }
    }
    if ($MissingFast.Count -gt 0) {
        throw "SM0-P4 $($Profile.label) contains measured legacy/fallback transfers: $($MissingFast -join ', ')"
    }

    $EvidenceProfiles.Add([pscustomobject][ordered]@{
        label = [string]$Profile.label
        measured_transfer_count = $MeasuredIds.Count
        p4_fast_transfer_count = $FastIds.Count
        all_measured_transfers_p4_fast = $true
        child_summary = $ChildSummaryPath
    })
}

$EvidencePath = Join-Path $MatrixDir "p4-fast-evidence-summary.json"
$Evidence = [ordered]@{
    schema = "distributed_world_simulator.sm0_p4_fast_evidence_summary.v1"
    git_head = [string]$Matrix.git_head
    result = "PASS"
    rule = "Every client-measured handoff in every WAN profile has a matching SM0_P4_FAST_COMMIT_ACCEPTED server event and aggregate A+B writer audit passed in the child matrix runner."
    recovery_root = $RecoveryRoot
    profiles = @($EvidenceProfiles)
    source_matrix = $MatrixSummaryPath
}
$Evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EvidencePath -Encoding UTF8

Write-Host ""
Write-Host "SM0-P4 controlled WAN matrix fast-path evidence: PASS" -ForegroundColor Green
foreach ($Profile in $EvidenceProfiles) {
    Write-Host ("  {0,-6}: measured={1} P4-fast-evidenced={2}" -f $Profile.label, $Profile.measured_transfer_count, $Profile.p4_fast_transfer_count)
}
Write-Host "  recovery: $RecoveryRoot"
Write-Host "  evidence: $EvidencePath"
exit 0
