[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LogDirectory,

    [ValidateRange(1, 1000)]
    [int]$ExpectedHandoffs = 4
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
    throw "SM0 log directory not found: $LogDirectory"
}

$RequiredLogs = @(
    (Join-Path $LogDirectory "server-a.log"),
    (Join-Path $LogDirectory "server-b.log"),
    (Join-Path $LogDirectory "client.log")
)

foreach ($Path in $RequiredLogs) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required SM0 log is missing: $Path"
    }
}

$Failures = New-Object System.Collections.Generic.List[string]
$Events = New-Object System.Collections.Generic.List[object]

foreach ($Path in $RequiredLogs) {
    $Lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    foreach ($Line in $Lines) {
        if ($Line -match '^\[SM0_EVENT\]\s+(\{.*\})\s*$') {
            try {
                $Event = $Matches[1] | ConvertFrom-Json
                Add-Member -InputObject $Event -NotePropertyName source_log -NotePropertyValue ([IO.Path]::GetFileName($Path)) -Force
                $Events.Add($Event)
            }
            catch {
                $Failures.Add("Unparseable SM0_EVENT in $([IO.Path]::GetFileName($Path)): $Line")
            }
        }
    }

    $BadText = Select-String -LiteralPath $Path -Pattern @(
        'SCRIPT ERROR',
        '^ERROR:',
        'SM0_INVARIANT_VIOLATION'
    ) -ErrorAction SilentlyContinue
    foreach ($Match in @($BadText)) {
        $Failures.Add("$([IO.Path]::GetFileName($Path)):$($Match.LineNumber): $($Match.Line.Trim())")
    }
}

function Get-Sm0Events {
    param([string]$Name)
    return @($Events | Where-Object { $_.event -eq $Name })
}

$ServerReady = @(Get-Sm0Events "SM0_SERVER_READY")
$PeerSynced = @(Get-Sm0Events "SM0_AUTHORITY_PEER_SYNCED")
$DirectoryReady = @(Get-Sm0Events "SM0_DIRECTORY_READY")
$Crossings = @(Get-Sm0Events "SM0_CROSSING_COMPLETED")
$Acceptance = @(Get-Sm0Events "SM0_ACCEPTANCE_RESULT")
$Violations = @(Get-Sm0Events "SM0_INVARIANT_VIOLATION")

if ($ServerReady.Count -lt 2) { $Failures.Add("Expected 2 SM0_SERVER_READY events, got $($ServerReady.Count)") }
if ($PeerSynced.Count -lt 2) { $Failures.Add("Expected both authority peers synchronized, got $($PeerSynced.Count) events") }
if ($DirectoryReady.Count -lt 2) { $Failures.Add("Expected both directories ready, got $($DirectoryReady.Count) events") }
if ($Crossings.Count -ne $ExpectedHandoffs) { $Failures.Add("Expected $ExpectedHandoffs completed handoffs, got $($Crossings.Count)") }
if ($Violations.Count -gt 0) { $Failures.Add("Structured invariant violations: $($Violations.Count)") }
if ($Acceptance.Count -lt 1) { $Failures.Add("Missing SM0_ACCEPTANCE_RESULT") }

$ClientResultPath = Join-Path $LogDirectory "client-result.json"
$ClientResult = $null
if (Test-Path -LiteralPath $ClientResultPath -PathType Leaf) {
    try { $ClientResult = Get-Content -LiteralPath $ClientResultPath -Raw | ConvertFrom-Json }
    catch { $Failures.Add("client-result.json is invalid JSON") }
}
else {
    $Failures.Add("client-result.json is missing")
}

if ($null -ne $ClientResult) {
    if ($ClientResult.result -ne "PASS") { $Failures.Add("Client result is not PASS: $($ClientResult.result) $($ClientResult.error_code)") }
    if ([int]$ClientResult.handoffs_completed -ne $ExpectedHandoffs) { $Failures.Add("Client reported $($ClientResult.handoffs_completed) handoffs; expected $ExpectedHandoffs") }
    if ([int]$ClientResult.identity_changes -ne 0) { $Failures.Add("Player identity changed $($ClientResult.identity_changes) times") }
    if ($ClientResult.logical_player_id -ne "a") { $Failures.Add("Unexpected logical player id: $($ClientResult.logical_player_id)") }
    if ($ClientResult.player_entity_id -ne "player/a") { $Failures.Add("Unexpected player entity id: $($ClientResult.player_entity_id)") }
    $ExpectedEndEpoch = 1 + $ExpectedHandoffs
    if ([int]$ClientResult.authority_epoch_end -ne $ExpectedEndEpoch) { $Failures.Add("Authority epoch ended at $($ClientResult.authority_epoch_end); expected $ExpectedEndEpoch") }
}

$PreviousEpoch = 1
$ExpectedAuthority = "authority/sm0/b"
foreach ($Crossing in @($Crossings | Sort-Object { [int]$_.handoff_index })) {
    $Directory = $Crossing.directory
    $Epoch = [int]$Directory.authority_epoch
    if ($Epoch -ne ($PreviousEpoch + 1)) {
        $Failures.Add("Non-monotonic authority epoch at handoff $($Crossing.handoff_index): $PreviousEpoch -> $Epoch")
    }
    if ($Directory.owner_authority_id -ne $ExpectedAuthority) {
        $Failures.Add("Unexpected owner at handoff $($Crossing.handoff_index): $($Directory.owner_authority_id), expected $ExpectedAuthority")
    }
    if ($Crossing.player.logical_player_id -ne "a" -or $Crossing.player.player_entity_id -ne "player/a") {
        $Failures.Add("Player identity mismatch at handoff $($Crossing.handoff_index)")
    }
    $PreviousEpoch = $Epoch
    $ExpectedAuthority = if ($ExpectedAuthority -eq "authority/sm0/b") { "authority/sm0/a" } else { "authority/sm0/b" }
}

$TransferIds = @($Crossings | ForEach-Object { [string]$_.transfer_id } | Where-Object { $_ } | Select-Object -Unique)
$RequiredTransferPhases = @(
    "SM0_SOURCE_FROZEN",
    "SM0_HANDOFF_PREPARED",
    "SM0_DIRECTORY_COMMITTED",
    "SM0_SOURCE_RETIRED",
    "SM0_TARGET_AUTHORITY_COMMITTED",
    "SM0_TARGET_ACTIVATED"
)

foreach ($TransferId in $TransferIds) {
    $TransferEvents = @($Events | Where-Object { [string]$_.transfer_id -eq $TransferId })
    foreach ($Phase in $RequiredTransferPhases) {
        if (@($TransferEvents | Where-Object { $_.event -eq $Phase }).Count -lt 1) {
            $Failures.Add("Transfer $TransferId is missing phase $Phase")
        }
    }
    $BadWriters = @($TransferEvents | Where-Object { $_.writer_count -ne $null -and [int]$_.writer_count -gt 1 })
    if ($BadWriters.Count -gt 0) {
        $Failures.Add("Transfer $TransferId observed writer_count > 1")
    }
}

$ControlEvents = @($Events | Where-Object {
    $_.event -in @("SM0_SERVER_READY", "SM0_AUTHORITY_PEER_SYNCED", "SM0_DIRECTORY_READY", "SM0_DIRECTORY_CONVERGED", "SM0_DIRECTORY_COMMITTED")
})
$HandoffEvents = @($Events | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.transfer_id) })

$ControlPath = Join-Path $LogDirectory "control.jsonl"
$HandoffsPath = Join-Path $LogDirectory "handoffs.jsonl"
$ControlEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 } | Set-Content -LiteralPath $ControlPath -Encoding UTF8
$HandoffEvents | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 20 } | Set-Content -LiteralPath $HandoffsPath -Encoding UTF8

$Summary = [ordered]@{
    schema = "distributed_world_simulator.sm0_acceptance_summary.v1"
    result = if ($Failures.Count -eq 0) { "PASS" } else { "FAIL" }
    expected_handoffs = $ExpectedHandoffs
    handoffs_completed = $Crossings.Count
    server_ready_events = $ServerReady.Count
    peer_synced_events = $PeerSynced.Count
    directory_ready_events = $DirectoryReady.Count
    invariant_violation_count = $Violations.Count
    unexpected_error_count = $Failures.Count
    player_identity_changes = if ($null -ne $ClientResult) { [int]$ClientResult.identity_changes } else { -1 }
    authority_epoch_start = 1
    authority_epoch_end = if ($null -ne $ClientResult) { [int]$ClientResult.authority_epoch_end } else { 0 }
    final_authority_id = if ($null -ne $ClientResult) { [string]$ClientResult.final_authority_id } else { "" }
    failures = @($Failures)
}

$SummaryPath = Join-Path $LogDirectory "summary.json"
$Summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

Write-Host ""
Write-Host "SM0 log analysis: $($Summary.result)" -ForegroundColor $(if ($Failures.Count -eq 0) { "Green" } else { "Red" })
Write-Host "  handoffs : $($Crossings.Count) / $ExpectedHandoffs"
Write-Host "  events   : $($Events.Count)"
Write-Host "  summary  : $SummaryPath"
Write-Host "  handoffs : $HandoffsPath"
Write-Host "  control  : $ControlPath"

if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:" -ForegroundColor Red
    foreach ($Failure in $Failures) {
        Write-Host "  - $Failure" -ForegroundColor Red
    }
    exit 1
}

exit 0
