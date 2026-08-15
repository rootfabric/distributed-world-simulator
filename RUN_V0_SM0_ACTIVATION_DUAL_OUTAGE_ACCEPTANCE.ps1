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
$FaultProfile = "h3-activation-dual-outage-before-ack-v1"
if ($Final) {
    $Handoffs = 6
    if ($TimeoutSeconds -lt 300) { $TimeoutSeconds = 300 }
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-H3.5 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH35"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H35Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Stop-H35 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H35Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H35; exit 0 }
if ($Restart) { Stop-H35 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H3.5 requires a clean worktree:`n$($StatusBefore -join "`n")"
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
Write-Host "[SM0-H3.5] Running healthy preflight before activation total outage..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H3.5 healthy preflight failed." }

function Invoke-H35CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H3.5] Compile check: $ScriptPath"
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
    if ($Code -ne 0) { throw "SM0-H3.5 compile check failed: $ScriptPath (exit $Code)" }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_transaction_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"
)) { Invoke-H35CompileCheck $ScriptPath }

function Invoke-H35Regression([string]$Label, [string]$ScriptPath) {
    Write-Host "[SM0-H3.5] Running $Label..."
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED
    $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H3.5 regression failed: $Label (exit $Code)" }
}

Invoke-H35Regression "transaction recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd"
Invoke-H35Regression "active-owner recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
Invoke-H35Regression "source-retire recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"

function Test-H35PortFree([int]$Port) {
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

function Wait-H35Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $AllFree = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H35PortFree $Port)) { $AllFree = $false; break }
        }
        if ($AllFree) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H35([string]$Value) { return '"' + $Value + '"' }

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
$SummaryPath = Join-Path $LogDir "h35-summary.json"

function Write-H35Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H35Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H35 $ProjectRoot),
        "--log-file", (Quote-H35 $Log),
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
    Write-H35Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H35Client([string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H35 $ProjectRoot),
        "--log-file", (Quote-H35 $CLog),
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
    Write-H35Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H35Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Get-H35Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @($Events) }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Events += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Events)
}

function Get-H35Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Recovery snapshot is missing: $Path" }
    return [ordered]@{ path = $Path; value = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
}

$A1 = $null; $A2 = $null; $B1 = $null; $B2 = $null; $C = $null; $Exit = 1
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H35PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H35Log "SM0-H3.5 start HEAD=$Head handoffs=$Handoffs profile=$FaultProfile boundary=after-active-owner-persist-before-activate-ack"

    $A1 = Start-H35Godot "server-a-source" $A1Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )
    $B1 = Start-H35Godot "server-b-activation-target" $B1Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )

    $State = [ordered]@{
        schema = "distributed_world_simulator.sm0_h35_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = @(
            [ordered]@{ role = "server-a-source"; pid = $A1.Id },
            [ordered]@{ role = "server-b-activation-target"; pid = $B1.Id }
        )
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H35Marker $A1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A1 20
    Wait-H35Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H35Marker $A1Log '"event":"SM0_RECOVERY_ENABLED"' $A1 20
    Wait-H35Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H35Marker $A1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $A1 20
    Wait-H35Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H35Client @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$Handoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult"
    )
    $State.processes += [ordered]@{ role = "client"; pid = $C.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H35Marker $B1Log '"crash_point":"DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK"' $B1 40
    Wait-H35Marker $A1Log '"event":"SM0_SOURCE_TRANSFER_COMPLETE"' $A1 20

    $EA1 = @(Get-H35Events $A1Log)
    $EB1 = @(Get-H35Events $B1Log)
    $ECBefore = @(Get-H35Events $CLog)
    $Crash = @($EB1 | Where-Object {
        $_.event -eq "SM0_H3_CRASH_POINT" -and $_.crash_point -eq "DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK"
    })
    if ($Crash.Count -ne 1) { throw "Expected exactly one H3.5 activation crash point, got $($Crash.Count)." }
    $TransferId = [string]$Crash[0].transfer_id
    $BGeneration = [int]$Crash[0].recovery_generation
    if ([string]::IsNullOrWhiteSpace($TransferId) -or $BGeneration -lt 1) { throw "Invalid H3.5 crash metadata." }

    $BCommitEvents = @($EB1 | Where-Object {
        $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BCommitEvents.Count -ne 1) { throw "Expected exactly one target commit before H3.5 outage." }
    $BActivated = @($EB1 | Where-Object {
        $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BActivated.Count -lt 1) { throw "Target was not activated before H3.5 outage." }
    $BActiveDurable = @($EB1 | Where-Object {
        $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and $_.message_type -eq "ACTIVATE_ACK" -and [int]$_.generation -eq $BGeneration
    })
    if ($BActiveDurable.Count -lt 1) { throw "ACTIVE_OWNER was not durable before suppressed ACTIVATE_ACK." }
    $BActivateSuppressed = @($EB1 | Where-Object {
        $_.event -eq "SM0_H3_TARGET_SEND_SUPPRESSED" -and $_.message_type -eq "ACTIVATE_ACK" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($BActivateSuppressed.Count -ne 1) { throw "H3.5 ACTIVATE_ACK suppression evidence missing." }

    $ASourceComplete = @($EA1 | Where-Object {
        $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ASourceComplete.Count -ne 1) { throw "Source transfer tracking was not completed before H3.5 outage." }
    $ASourcePersisted = @($EA1 | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ASourcePersisted.Count -ne 1) { throw "A durable SOURCE_RETIRED checkpoint missing before H3.5 outage." }
    $AGeneration = [int]$ASourcePersisted[0].generation

    if (@($ECBefore | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" }).Count -ne 0) {
        throw "Client completed crossing before H3.5 outage."
    }

    $ASnapshotRecord = Get-H35Snapshot "authority-a" $AGeneration
    $ASnapshot = $ASnapshotRecord.value
    if ([string]$ASnapshot.phase -ne "SOURCE_RETIRED" -or [string]$ASnapshot.transfer_id -ne $TransferId) {
        throw "A durable checkpoint is not matching SOURCE_RETIRED."
    }
    if ([string]$ASnapshot.directory.owner_authority_id -ne "authority/sm0/b") { throw "A durable directory does not point to B." }

    $BSnapshotRecord = Get-H35Snapshot "authority-b" $BGeneration
    $BSnapshot = $BSnapshotRecord.value
    if ([string]$BSnapshot.phase -ne "ACTIVE_OWNER") { throw "B crash snapshot is not ACTIVE_OWNER." }
    if ([string]$BSnapshot.directory.owner_authority_id -ne "authority/sm0/b") { throw "B ACTIVE_OWNER snapshot does not own directory." }
    $BCommittedProperty = $BSnapshot.committed_transfers.PSObject.Properties[$TransferId]
    if ($null -eq $BCommittedProperty) { throw "B ACTIVE_OWNER snapshot lost committed transfer metadata." }

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
    if ((Test-H35Alive $A1Pid) -or (Test-H35Alive $B1Pid)) { throw "At least one authority survived H3.5 total outage." }
    $C.Refresh()
    if ($C.HasExited) { throw "Client exited during H3.5 zero-authority interval." }
    Wait-H35Ports @(24580,24581,24680,24681)
    Write-H35Log "Activation total outage established transfer=${TransferId}: A completed source tracking but durable SOURCE_RETIRED gen=$AGeneration remains, B ACTIVE_OWNER gen=$BGeneration, A PID=$A1Pid and B PID=$B1Pid dead, gap=${KillRequestGapMs}ms, client PID=$($C.Id) still ACTIVATING."

    $B2 = Start-H35Godot "server-b-recovered-active" $B2Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--transaction-recovery=1"
    )
    $A2 = Start-H35Godot "server-a-recovered-retired" $A2Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--transaction-recovery=1"
    )
    if ($B2.Id -eq $B1Pid -or $A2.Id -eq $A1Pid) { throw "Recovered authority unexpectedly reused crashed PID." }
    $State.processes += [ordered]@{ role = "server-b-recovered-active"; pid = $B2.Id }
    $State.processes += [ordered]@{ role = "server-a-recovered-retired"; pid = $A2.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H35Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $B2 20
    Wait-H35Marker $A2Log '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $A2 20
    Wait-H35Marker $B2Log '"event":"SM0_RECOVERY_SESSION_REBOUND"' $B2 40
    Wait-H35Marker $CLog '"event":"SM0_CROSSING_COMPLETED"' $C 45
    Write-H35Log "Recovered B completed the outstanding activation from durable ACTIVE_OWNER; recovered A replayed stale SOURCE_RETIRED tracking idempotently; same client completed crossing #1."

    $EA2Now = @(Get-H35Events $A2Log)
    $EB2Now = @(Get-H35Events $B2Log)
    $BRestored = @($EB2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $BGeneration
    })
    if ($BRestored.Count -ne 1) { throw "Recovered B did not restore exact ACTIVE_OWNER generation." }
    $ARestored = @($EA2Now | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $AGeneration -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ARestored.Count -ne 1 -or [int]$ARestored[0].writer_count -ne 0) {
        throw "Recovered A did not restore exact retired non-writer state."
    }
    if (@($EB2Now | Where-Object {
        $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
    }).Count -ne 0) { throw "H3.5 recovery created duplicate target commit/import." }
    if ((Select-String -LiteralPath $A2Log,$B2Log -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) {
        throw "H3.5 recovery hit SM0_COMMIT_WITHOUT_PREPARE."
    }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 15)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A2.Refresh(); $B2.Refresh()
        if ($A2.HasExited -or $B2.HasExited) { throw "Authority process exited after H3.5 recovery." }
    }
    if (-not $C.HasExited) { throw "Client timed out after H3.5 recovery." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A2,$B2)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $A1Log),(Get-Content -LiteralPath $A2Log)) | Set-Content -LiteralPath $ALog -Encoding UTF8
    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after H3.5 activation outage." }

    $AllEvents = @(Get-H35Events $ALog) + @(Get-H35Events $BLog)
    if (@($AllEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) {
        throw "Invariant violation observed in H3.5 authority logs."
    }
    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) {
        throw "Client H3.5 evidence failed."
    }
    $Crossings = @(Get-H35Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($Crossings.Count -ne $Handoffs) { throw "Crossing event count mismatch after H3.5 recovery." }
    $ExpectedEpoch = $Handoffs + 1
    if ([int]$Result.authority_epoch_end -ne $ExpectedEpoch) {
        throw "Final directory epoch mismatch: expected $ExpectedEpoch got $($Result.authority_epoch_end)"
    }

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h35_activation_dual_outage_summary.v1"
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
        target_active_owner_generation = $BGeneration
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_epoch = [int]$Result.authority_epoch_end
        identity_changes = [int]$Result.identity_changes
        source_snapshot = $ASnapshotRecord.path
        target_active_snapshot = $BSnapshotRecord.path
        logs = $LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H3.5 durable activation dual-authority outage recovery: PASS" -ForegroundColor Green
    Write-Host "  same client PID       : $($C.Id)"
    Write-Host "  transfer              : $TransferId"
    Write-Host "  killed A PID          : $A1Pid"
    Write-Host "  killed B PID          : $B1Pid"
    Write-Host "  restarted A PID       : $($A2.Id)"
    Write-Host "  restarted B PID       : $($B2.Id)"
    Write-Host "  kill request gap      : $KillRequestGapMs ms"
    Write-Host "  A SOURCE_RETIRED gen  : $AGeneration"
    Write-Host "  B ACTIVE_OWNER gen    : $BGeneration"
    Write-Host "  duplicate target commit: 0"
    Write-Host "  handoffs              : $Handoffs / $Handoffs"
    Write-Host "  final directory epoch : $($Result.authority_epoch_end)"
    Write-Host "  identity changes      : 0"
    Write-Host "  logs                  : $LogDir"
    Write-Host "  summary               : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H3.5 FAIL: $($_.Exception.Message)" -ErrorAction Continue
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
                    Write-Host "[SM0-H3.5] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H3.5 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
