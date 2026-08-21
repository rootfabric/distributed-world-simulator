[CmdletBinding()]
param(
    [ValidateRange(2, 100)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$FaultProfile = "h3-commit-decision-dual-outage-v1"
if ($Final) {
    $Handoffs = 6
    if ($TimeoutSeconds -lt 300) { $TimeoutSeconds = 300 }
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-H3.4 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH34"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H34Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Stop-H34 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H34Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H34; exit 0 }
if ($Restart) { Stop-H34 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H3.4 requires a clean worktree:`n$($StatusBefore -join "`n")"
}
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate pre-existing UID sidecars." }
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{
    Handoffs = 2
    Restart = $true
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = 120
}
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H3.4] Running healthy preflight before commit-decision total outage..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H3.4 healthy preflight failed." }

function Invoke-H34CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H3.4] Compile check: $ScriptPath"
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H3.4 compile check failed: $ScriptPath (exit $Code)" }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd"
)) { Invoke-H34CompileCheck $ScriptPath }

Write-Host "[SM0-H3.4] Running transaction recovery regression..."
$OldRegression = $env:BREAKPOINT_RUNTIME_DISABLED
$HadRegression = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --path $ProjectRoot --script "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd"
    $RegressionCode = $LASTEXITCODE
}
finally {
    if ($HadRegression) { $env:BREAKPOINT_RUNTIME_DISABLED = $OldRegression }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
if ($RegressionCode -ne 0) { throw "SM0-H3.4 transaction recovery regression failed (exit $RegressionCode)." }

function Test-H34PortFree([int]$Port) {
    $Udp = $null
    try {
        $Udp = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $Udp.Client.ExclusiveAddressUse = $true
        $Udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    }
    catch { return $false }
    finally { if ($null -ne $Udp) { $Udp.Dispose() } }
}

function Wait-H34Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $AllFree = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H34PortFree $Port)) { $AllFree = $false; break }
        }
        if ($AllFree) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H34([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$A1Log = Join-Path $LogDir "server-a-before-outage.log"
$A2Log = Join-Path $LogDir "server-a-restarted.log"
$ALog = Join-Path $LogDir "server-a.log"
$B1Log = Join-Path $LogDir "server-b-before-outage.log"
$B2Log = Join-Path $LogDir "server-b-restarted.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h34-summary.json"

function Write-H34Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H34Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H34 $ProjectRoot),
        "--log-file", (Quote-H34 $Log),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--"
    ) + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-H34Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H34Client([string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H34 $ProjectRoot),
        "--log-file", (Quote-H34 $CLog),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--"
    ) + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-H34Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H34Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Get-H34Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @($Events) }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Events += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Events)
}

function Get-H34Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Recovery snapshot is missing: $Path" }
    return [ordered]@{ path = $Path; value = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
}

$A1 = $null; $A2 = $null; $B1 = $null; $B2 = $null; $C = $null; $Exit = 1
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H34PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H34Log "SM0-H3.4 start HEAD=$Head handoffs=$Handoffs profile=$FaultProfile boundary=after-target-commit-before-observation"

    $A1 = Start-H34Godot "server-a-retired-source" $A1Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )
    $B1 = Start-H34Godot "server-b-committed-target" $B1Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )

    $State = [ordered]@{
        schema = "distributed_world_simulator.sm0_h34_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = @(
            [ordered]@{ role = "server-a-retired-source"; pid = $A1.Id },
            [ordered]@{ role = "server-b-committed-target"; pid = $B1.Id }
        )
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H34Marker $A1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A1 20
    Wait-H34Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H34Marker $A1Log '"event":"SM0_RECOVERY_ENABLED"' $A1 20
    Wait-H34Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H34Marker $A1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $A1 20
    Wait-H34Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H34Client @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$Handoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult"
    )
    $State.processes += [ordered]@{ role = "client"; pid = $C.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H34Marker $B1Log '"crash_point":"DUAL_OUTAGE_AFTER_TARGET_COMMIT_BEFORE_OBSERVATION"' $B1 40
    Wait-H34Marker $A1Log '"message_type":"HANDOFF_REDIRECT"' $A1 20

    $EA1 = @(Get-H34Events $A1Log)
    $EB1 = @(Get-H34Events $B1Log)
    $ECBefore = @(Get-H34Events $CLog)
    $Crash = @($EB1 | Where-Object {
        $_.event -eq "SM0_H3_CRASH_POINT" -and $_.crash_point -eq "DUAL_OUTAGE_AFTER_TARGET_COMMIT_BEFORE_OBSERVATION"
    })
    if ($Crash.Count -ne 1) { throw "Expected exactly one H3.4 target commit boundary, got $($Crash.Count)." }
    $TransferId = [string]$Crash[0].transfer_id
    $BGeneration = [int]$Crash[0].recovery_generation
    if ([string]::IsNullOrWhiteSpace($TransferId) -or $BGeneration -lt 1) { throw "Invalid H3.4 target crash metadata." }

    $BCommitEvents = @($EB1 | Where-Object {
        $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BCommitEvents.Count -ne 1 -or [int]$BCommitEvents[0].writer_count -ne 1) {
        throw "B did not create exactly one target commit decision before outage."
    }
    $BPersisted = @($EB1 | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "TARGET_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BPersisted.Count -ne 1 -or [int]$BPersisted[0].generation -ne $BGeneration) {
        throw "B TARGET_COMMITTED decision was not durably persisted at crash generation."
    }
    $BAckSuppressed = @($EB1 | Where-Object {
        $_.event -eq "SM0_H3_TARGET_SEND_SUPPRESSED" -and $_.message_type -eq "PLAYER_HANDOFF_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BAckSuppressed.Count -ne 1) { throw "H3.4 target COMMITTED ACK suppression missing." }

    $ASourcePersisted = @($EA1 | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ASourcePersisted.Count -ne 1) { throw "A matching SOURCE_RETIRED snapshot missing." }
    $AGeneration = [int]$ASourcePersisted[0].generation
    $ARedirectSuppressed = @($EA1 | Where-Object {
        $_.event -eq "SM0_H3_SOURCE_SEND_SUPPRESSED" -and $_.message_type -eq "HANDOFF_REDIRECT" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ARedirectSuppressed.Count -ne 1) { throw "H3.4 source redirect suppression missing." }
    if (@($EA1 | Where-Object {
        $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $TransferId
    }).Count -ne 0) { throw "Source completed transfer tracking before H3.4 outage." }
    if (@($ECBefore | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" }).Count -ne 0) {
        throw "Client completed crossing before H3.4 total outage."
    }

    $ASnapshotRecord = Get-H34Snapshot "authority-a" $AGeneration
    $ASnapshot = $ASnapshotRecord.value
    if ([string]$ASnapshot.phase -ne "SOURCE_RETIRED" -or [string]$ASnapshot.transfer_id -ne $TransferId) {
        throw "A snapshot is not SOURCE_RETIRED for H3.4 transfer."
    }
    if ([string]$ASnapshot.directory.owner_authority_id -ne "authority/sm0/b") { throw "A durable directory does not point to B." }
    $ASource = $ASnapshot.source_transfer
    if ([string]$ASource.stage -ne "COMMIT_SENT" -or [bool]$ASource.target_committed -or [bool]$ASource.client_redirect_acked) {
        throw "A durable source viewpoint already observed commit or redirect ACK."
    }

    $BSnapshotRecord = Get-H34Snapshot "authority-b" $BGeneration
    $BSnapshot = $BSnapshotRecord.value
    if ([string]$BSnapshot.phase -ne "TARGET_COMMITTED" -or [string]$BSnapshot.transfer_id -ne $TransferId) {
        throw "B snapshot is not TARGET_COMMITTED for H3.4 transfer."
    }
    if ([string]$BSnapshot.directory.owner_authority_id -ne "authority/sm0/b") { throw "B committed snapshot does not own directory." }
    $BCommittedMap = $BSnapshot.committed_transfers
    $BCommittedProperty = $BCommittedMap.PSObject.Properties[$TransferId]
    if ($null -eq $BCommittedProperty) { throw "B durable committed map lost H3.4 transfer." }

    $A1Pid = $A1.Id
    $B1Pid = $B1.Id
    $BKillRequestMs = [Environment]::TickCount64
    Stop-Process -Id $B1Pid -Force -ErrorAction Stop
    $AKillRequestMs = [Environment]::TickCount64
    Stop-Process -Id $A1Pid -Force -ErrorAction Stop
    $KillRequestGapMs = [Math]::Abs([long]$AKillRequestMs - [long]$BKillRequestMs)
    if ($KillRequestGapMs -gt 500) { throw "Dual-authority kill request gap exceeded 500 ms: $KillRequestGapMs" }
    try { $null = $B1.WaitForExit(5000) } catch {}
    try { $null = $A1.WaitForExit(5000) } catch {}
    if ((Test-H34Alive $A1Pid) -or (Test-H34Alive $B1Pid)) { throw "At least one authority survived H3.4 total outage." }
    $C.Refresh()
    if ($C.HasExited) { throw "Client exited during H3.4 zero-authority interval." }
    Wait-H34Ports @(24580,24581,24680,24681)
    Write-H34Log "Commit-decision total outage established transfer=${TransferId}: A SOURCE_RETIRED gen=$AGeneration, B TARGET_COMMITTED gen=$BGeneration, A PID=$A1Pid and B PID=$B1Pid dead, gap=${KillRequestGapMs}ms, client PID=$($C.Id) alive."

    $B2 = Start-H34Godot "server-b-recovered-committed" $B2Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--transaction-recovery=1"
    )
    if ($B2.Id -eq $B1Pid) { throw "Recovered B unexpectedly reused crashed PID." }
    Wait-H34Marker $B2Log '"phase":"TARGET_COMMITTED"' $B2 20

    $A2 = Start-H34Godot "server-a-recovered-retired" $A2Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer_control-port=24681", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--transaction-recovery=1"
    )
    if ($A2.Id -eq $A1Pid) { throw "Recovered A unexpectedly reused crashed PID." }
    $State.processes += [ordered]@{ role = "server-b-recovered-committed"; pid = $B2.Id }
    $State.processes += [ordered]@{ role = "server-a-recovered-retired"; pid = $A2.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H34Marker $A2Log '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $A2 20
    Wait-H34Marker $B2Log '"event":"SM0_RECOVERY_SESSION_REBOUND"' $B2 40
    Wait-H34Marker $A2Log '"event":"SM0_SOURCE_TRANSFER_COMPLETE"' $A2 40
    Wait-H34Marker $CLog '"event":"SM0_CROSSING_COMPLETED"' $C 45
    Write-H34Log "Recovered B retained the durable commit decision; replayed COMMIT was idempotent and the same client completed crossing #1."

    $EA2Now = @(Get-H34Events $A2Log)
    $EB2Now = @(Get-H34Events $B2Log)
    $ARestored = @($EA2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $AGeneration -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ARestored.Count -ne 1 -or [int]$ARestored[0].writer_count -ne 0) {
        throw "Recovered A did not restore exact SOURCE_RETIRED state as non-writer."
    }
    $BRestored = @($EB2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "TARGET_COMMITTED" -and [int]$_.generation -eq $BGeneration -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BRestored.Count -ne 1) { throw "Recovered B did not restore exact TARGET_COMMITTED generation." }
    if (@($EB2Now | Where-Object {
        $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    }).Count -ne 0) { throw "Replayed COMMIT created a second target commit decision." }
    if (@($EB2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "TARGET_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    }).Count -ne 0) { throw "Replayed COMMIT persisted a second TARGET_COMMITTED generation." }
    $BRebound = @($EB2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_SESSION_REBOUND" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BRebound.Count -ne 1) { throw "Recovered committed target session was not rebound exactly once." }
    if ((Select-String -LiteralPath $A2Log,$B2Log -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) {
        throw "Recovered H3.4 transaction hit SM0_COMMIT_WITHOUT_PREPARE."
    }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 15)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A2.Refresh(); $B2.Refresh()
        if ($A2.HasExited -or $B2.HasExited) { throw "Authority process exited after H3.4 recovery." }
    }
    if (-not $C.HasExited) { throw "Client timed out after H3.4 recovery." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A2,$B2)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $A1Log),(Get-Content -LiteralPath $A2Log)) | Set-Content -LiteralPath $ALog -Encoding UTF8
    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after H3.4 commit-decision outage." }

    $AllEvents = @(Get-H34Events $ALog) + @(Get-H34Events $BLog)
    if (@($AllEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) {
        throw "Invariant violation observed in H3.4 authority logs."
    }
    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) {
        throw "Client H3.4 evidence failed."
    }
    $Crossings = @(Get-H34Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($Crossings.Count -ne $Handoffs) { throw "Crossing event count mismatch after H3.4 recovery." }
    $ExpectedEpoch = $Handoffs + 1
    if ([int]$Result.authority_epoch_end -ne $ExpectedEpoch) {
        throw "Final directory epoch mismatch: expected $ExpectedEpoch got $($Result.authority_epoch_end)"
    }

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h34_commit_decision_dual_outage_summary.v1"
        result = "PASS"
        git_head = $Head
        transfer_id = $TransferId
        client_pid = $C.Id
        killed_a_pid = $A1Pid
        killed_b_pid = $B1Pid
        restarted_a_pid = $A2.Id
        restarted_b_pid = $B2.Id
        kill_request_gap_ms = $KillRequestGapMs
        source_retired_generation = $AGeneration
        target_committed_generation = $BGeneration
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_epoch = [int]$Result.authority_epoch_end
        identity_changes = [int]$Result.identity_changes
        source_snapshot = $ASnapshotRecord.path
        target_committed_snapshot = $BSnapshotRecord.path
        logs = $LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H3.4 durable commit-decision dual-authority outage recovery: PASS" -ForegroundColor Green
    Write-Host "  same client PID       : $($C.Id)"
    Write-Host "  transfer              : $TransferId"
    Write-Host "  killed A PID          : $A1Pid"
    Write-Host "  killed B PID          : $B1Pid"
    Write-Host "  restarted A PID       : $($A2.Id)"
    Write-Host "  restarted B PID       : $($B2.Id)"
    Write-Host "  kill request gap      : $KillRequestGapMs ms"
    Write-Host "  A SOURCE_RETIRED gen  : $AGeneration"
    Write-Host "  B TARGET_COMMITTED gen: $BGeneration"
    Write-Host "  duplicate target commit: 0"
    Write-Host "  handoffs              : $Handoffs / $Handoffs"
    Write-Host "  final directory epoch : $($Result.authority_epoch_end)"
    Write-Host "  identity changes      : 0"
    Write-Host "  logs                  : $LogDir"
    Write-Host "  summary               : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H3.4 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A1,$A2,$B1,$B2)) {
        if ($null -ne $Process) {
            try { $Process.Refresh(); if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } } catch {}
        }
    }
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    $UidAfter = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
    if ($LASTEXITCODE -eq 0) {
        foreach ($RelativeUid in $UidAfter) {
            $RelativeUidText = [string]$RelativeUid
            if (-not $UidBeforeSet.ContainsKey($RelativeUidText)) {
                $GeneratedPath = Join-Path $ProjectRoot $RelativeUidText
                if (Test-Path -LiteralPath $GeneratedPath -PathType Leaf) {
                    Remove-Item -LiteralPath $GeneratedPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[SM0-H3.4] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H3.4 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
