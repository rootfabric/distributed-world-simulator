[CmdletBinding()]
param(
    [ValidateRange(2, 100)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 150
)

$ErrorActionPreference = "Stop"
$CrashProfile = "h2-active-owner-crash-after-move-persist-v1"
if ($Final) {
    $Handoffs = 6
    if ($TimeoutSeconds -lt 240) { $TimeoutSeconds = 240 }
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-H3.2 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH32"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H32Alive([int]$PidValue) {
    try {
        Get-Process -Id $PidValue -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function Stop-H32 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H32Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H32; exit 0 }
if ($Restart) { Stop-H32 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H3.2 requires a clean worktree:`n$($StatusBefore -join "`n")"
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
Write-Host "[SM0-H3.2] Running healthy preflight before simultaneous dual-authority outage..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H3.2 healthy preflight failed." }

function Invoke-H32CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H3.2] Compile check: $ScriptPath"
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
    if ($Code -ne 0) { throw "SM0-H3.2 compile check failed: $ScriptPath (exit $Code)" }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
)) { Invoke-H32CompileCheck $ScriptPath }

Write-Host "[SM0-H3.2] Running shared active-owner durable replay regression..."
$OldRegression = $env:BREAKPOINT_RUNTIME_DISABLED
$HadRegression = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --path $ProjectRoot --script "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
    $RegressionCode = $LASTEXITCODE
}
finally {
    if ($HadRegression) { $env:BREAKPOINT_RUNTIME_DISABLED = $OldRegression }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
if ($RegressionCode -ne 0) { throw "SM0-H3.2 active owner recovery regression failed (exit $RegressionCode)." }

function Test-H32PortFree([int]$Port) {
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

function Wait-H32Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $Ok = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H32PortFree $Port)) { $Ok = $false; break }
        }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H32([string]$Value) { return '"' + $Value + '"' }

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
$SummaryPath = Join-Path $LogDir "h32-summary.json"

function Write-H32Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H32Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H32 $ProjectRoot),
        "--log-file", (Quote-H32 $Log),
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
    Write-H32Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H32Client([string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H32 $ProjectRoot),
        "--log-file", (Quote-H32 $CLog),
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
    Write-H32Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H32Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Get-H32Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @($Events) }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') {
            $Events += ($Matches[1] | ConvertFrom-Json)
        }
    }
    return @($Events)
}

function Get-H32Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Recovery snapshot is missing: $Path"
    }
    return [ordered]@{ path = $Path; value = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
}

$A1 = $null
$A2 = $null
$B1 = $null
$B2 = $null
$C = $null
$Exit = 1

try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H32PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H32Log "SM0-H3.2 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile outage=both-after-A-to-B settle_steps=1"

    $A1 = Start-H32Godot "server-a-before-outage" $A1Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    $B1 = Start-H32Godot "server-b-outage-trigger" $B1Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--fault-profile=$CrashProfile", "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )

    $State = [ordered]@{
        schema = "distributed_world_simulator.sm0_h32_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = @(
            [ordered]@{ role = "server-a-before-outage"; pid = $A1.Id },
            [ordered]@{ role = "server-b-outage-trigger"; pid = $B1.Id }
        )
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H32Marker $A1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A1 20
    Wait-H32Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H32Marker $A1Log '"event":"SM0_RECOVERY_ENABLED"' $A1 20
    Wait-H32Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H32Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H32Client @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$Handoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult",
        "--post-handoff-settle-steps=1"
    )
    $State.processes += [ordered]@{ role = "client"; pid = $C.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    # Crossing #1 must complete cleanly before the total-outage fault boundary.
    Wait-H32Marker $CLog '"event":"SM0_CROSSING_COMPLETED"' $C 30
    $CrossingsBeforeOutage = @(Get-H32Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsBeforeOutage.Count -ne 1) { throw "H3.2 requires exactly one A -> B crossing before outage." }
    $FirstCrossing = $CrossingsBeforeOutage[0]
    if ([int]$FirstCrossing.handoff_index -ne 1 -or [string]$FirstCrossing.authority_id -ne "authority/sm0/b" -or [string]$FirstCrossing.zone_id -ne "zone/earth/sm0/east") {
        throw "First crossing did not activate authority B."
    }
    if ([string]$FirstCrossing.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$FirstCrossing.directory.authority_epoch -ne 2) {
        throw "First crossing did not establish exact B directory epoch 2."
    }
    $TransferId = [string]$FirstCrossing.transfer_id
    if ([string]::IsNullOrWhiteSpace($TransferId)) { throw "First crossing transfer id is missing." }

    # Require source tracking to have finished before H3.2. This keeps the
    # simultaneous outage outside the handoff transaction itself.
    Wait-H32Marker $A1Log '"event":"SM0_SOURCE_TRANSFER_COMPLETE"' $A1 15
    $A1BeforeOutage = @(Get-H32Events $A1Log)
    $SourceComplete = @($A1BeforeOutage | Where-Object { $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $TransferId })
    if ($SourceComplete.Count -ne 1) { throw "A -> B source tracking was not complete before total outage." }

    $ARetiredPersisted = @($A1BeforeOutage | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ARetiredPersisted.Count -ne 1) { throw "A does not have exactly one durable SOURCE_RETIRED snapshot for crossing #1." }
    $AGeneration = [int]$ARetiredPersisted[0].generation
    if ($AGeneration -lt 1 -or [int]$ARetiredPersisted[0].writer_count -ne 0) { throw "A retired snapshot event is not a durable non-writer boundary." }
    $ASnapshotRecord = Get-H32Snapshot "authority-a" $AGeneration
    $ASnapshot = $ASnapshotRecord.value
    if ([string]$ASnapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1" -or [string]$ASnapshot.phase -ne "SOURCE_RETIRED") {
        throw "A recovery snapshot is not SOURCE_RETIRED."
    }
    if ([string]$ASnapshot.transfer_id -ne $TransferId -or [string]$ASnapshot.authority_id -ne "authority/sm0/a") {
        throw "A SOURCE_RETIRED snapshot does not match crossing #1."
    }
    if ([string]$ASnapshot.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$ASnapshot.directory.authority_epoch -ne 2) {
        throw "A retired snapshot does not preserve B ownership at epoch 2."
    }
    if ([string]$ASnapshot.source_transfer.transfer_id -ne $TransferId -or [string]$ASnapshot.source_transfer.stage -ne "COMMIT_SENT") {
        throw "A retired source transaction metadata is incomplete."
    }
    $ADurablePlayer = @($ASnapshot.gameplay_state.players.players | Where-Object { $_.logical_player_id -eq "a" })
    if ($ADurablePlayer.Count -ne 1 -or [string]$ADurablePlayer[0].player_entity_id -ne "player/a") {
        throw "A retired snapshot lost player identity."
    }
    if ([bool]$ADurablePlayer[0].connected -or -not [string]::IsNullOrEmpty([string]$ADurablePlayer[0].transport_session_id)) {
        throw "A retired snapshot contains a live writer session."
    }

    # B fault boundary: one MOVE inside EAST is durable but not ACKed.
    Wait-H32Marker $B1Log '"crash_point":"ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"' $B1 30
    $B1BeforeOutage = @(Get-H32Events $B1Log)
    $Crash = @($B1BeforeOutage | Where-Object {
        $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"
    })
    if ($Crash.Count -ne 1) { throw "Expected exactly one B active-owner outage marker, got $($Crash.Count)." }
    $BGeneration = [int]$Crash[0].recovery_generation
    $BSequence = [int]$Crash[0].last_input_sequence
    $BOwnership = [int]$Crash[0].ownership_epoch
    $BX = [double]$Crash[0].position.x
    if ($BGeneration -lt 1 -or $BSequence -lt 1 -or $BX -le 0.0) {
        throw "Invalid B total-outage boundary generation=$BGeneration sequence=$BSequence x=$BX"
    }
    if (@($B1BeforeOutage | Where-Object { $_.event -eq "SM0_HANDOFF_BEGIN" }).Count -ne 0) {
        throw "B began B -> A handoff before simultaneous outage."
    }
    $CrossingsAtOutage = @(Get-H32Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsAtOutage.Count -ne 1) { throw "Total outage was not isolated between crossing #1 and crossing #2." }

    $BActivePersisted = @($B1BeforeOutage | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $BGeneration
    })
    if ($BActivePersisted.Count -ne 1) { throw "Exact B ACTIVE_OWNER generation was not persisted before outage." }
    $BSnapshotRecord = Get-H32Snapshot "authority-b" $BGeneration
    $BSnapshot = $BSnapshotRecord.value
    if ([string]$BSnapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1" -or [string]$BSnapshot.phase -ne "ACTIVE_OWNER") {
        throw "B recovery snapshot is not ACTIVE_OWNER."
    }
    if ([string]$BSnapshot.authority_id -ne "authority/sm0/b" -or [string]$BSnapshot.zone_id -ne "zone/earth/sm0/east") {
        throw "B active snapshot authority/zone mismatch."
    }
    if ([string]$BSnapshot.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$BSnapshot.directory.authority_epoch -ne 2) {
        throw "B active snapshot does not preserve B ownership at epoch 2."
    }
    if ([int]$BSnapshot.source_transfer.last_input_sequence -ne $BSequence -or [int]$BSnapshot.source_transfer.ownership_epoch -ne $BOwnership) {
        throw "B active metadata does not match crash marker."
    }
    $BDurablePlayer = @($BSnapshot.gameplay_state.players.players | Where-Object { $_.logical_player_id -eq "a" })
    if ($BDurablePlayer.Count -ne 1 -or [string]$BDurablePlayer[0].player_entity_id -ne "player/a") {
        throw "B active snapshot lost player identity."
    }
    if ([bool]$BDurablePlayer[0].connected -or -not [string]::IsNullOrEmpty([string]$BDurablePlayer[0].transport_session_id)) {
        throw "B active snapshot contains a live transport session."
    }
    if ([int]$BDurablePlayer[0].last_input_sequence -ne $BSequence -or [Math]::Abs([double]$BDurablePlayer[0].position.x - $BX) -gt 0.000001) {
        throw "B durable movement does not match outage marker."
    }

    # Kill both authority processes before restarting either one. The calls are
    # necessarily sequential in PowerShell, but the bounded supervisor gap must
    # stay small and there is a real interval with zero live authority process.
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
    if (Test-H32Alive $A1Pid -or Test-H32Alive $B1Pid) { throw "At least one authority survived forced total outage." }
    $C.Refresh()
    if ($C.HasExited) { throw "Client exited during total-outage interval before server restart." }
    Wait-H32Ports @(24580,24581,24680,24681)
    Write-H32Log "Total outage established after A -> B: A PID=$A1Pid and B PID=$B1Pid dead; kill request gap=${KillRequestGapMs}ms; client PID=$($C.Id) remains alive."

    # Restart both from their own durable viewpoints. B is started first only as
    # process orchestration; durable directory state, not start order, owns truth.
    $B2 = Start-H32Godot "server-b-recovered" $B2Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    $A2 = Start-H32Godot "server-a-recovered" $A2Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    if ($B2.Id -eq $B1Pid -or $A2.Id -eq $A1Pid) { throw "Recovered authority unexpectedly reused its crashed PID." }
    $State.processes += [ordered]@{ role = "server-b-recovered"; pid = $B2.Id }
    $State.processes += [ordered]@{ role = "server-a-recovered"; pid = $A2.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H32Marker $B2Log '"event":"SM0_RECOVERY_RESTORED"' $B2 20
    Wait-H32Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $B2 20
    Wait-H32Marker $A2Log '"event":"SM0_RECOVERY_RESTORED"' $A2 20
    Wait-H32Marker $A2Log '"event":"SM0_RECOVERY_SOURCE_TRANSFER_RESUMED"' $A2 20
    Wait-H32Marker $B2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B2 30
    Wait-H32Marker $A2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A2 30
    Wait-H32Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_REBOUND"' $B2 30
    Write-H32Log "Both authorities restored after total outage; B rebound exact durable MOVE and A remained retired/non-writer. Waiting for final convergence."

    $A2EventsNow = @(Get-H32Events $A2Log)
    $B2EventsNow = @(Get-H32Events $B2Log)

    $ARestored = @($A2EventsNow | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $AGeneration -and [string]$_.transfer_id -eq $TransferId
    })
    if ($ARestored.Count -ne 1) { throw "Recovered A did not restore exact SOURCE_RETIRED generation." }
    if ([int]$ARestored[0].writer_count -ne 0 -or [string]$ARestored[0].directory.owner_authority_id -ne "authority/sm0/b") {
        throw "Recovered A restored as writer or with wrong directory owner."
    }
    $AResumed = @($A2EventsNow | Where-Object {
        $_.event -eq "SM0_RECOVERY_SOURCE_TRANSFER_RESUMED" -and [string]$_.transfer_id -eq $TransferId
    })
    if ($AResumed.Count -ne 1 -or [int]$AResumed[0].writer_count -ne 0) {
        throw "Recovered A did not resume retired source tracking as non-writer."
    }
    if (@($A2EventsNow | Where-Object { $_.event -eq "SM0_RECOVERY_ACTIVE_OWNER_REBOUND" }).Count -ne 0) {
        throw "Recovered retired A incorrectly rebound as active owner during total-outage recovery."
    }

    $BRestored = @($B2EventsNow | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $BGeneration
    })
    if ($BRestored.Count -ne 1 -or [string]$BRestored[0].directory.owner_authority_id -ne "authority/sm0/b") {
        throw "Recovered B did not restore exact ACTIVE_OWNER generation owned by B."
    }
    $BRebound = @($B2EventsNow | Where-Object { $_.event -eq "SM0_RECOVERY_ACTIVE_OWNER_REBOUND" })
    if ($BRebound.Count -lt 1) { throw "Recovered B did not rebind client after total outage." }
    $FirstBRebound = $BRebound[0]
    if (-not [bool]$FirstBRebound.duplicate_durable_input) { throw "Recovered B retry was not exact durable replay." }
    if ([int]$FirstBRebound.last_input_sequence -ne $BSequence) { throw "Recovered B sequence differs from durable outage sequence." }
    if ([int]$FirstBRebound.previous_ownership_epoch -ne $BOwnership -or [int]$FirstBRebound.ownership_epoch -ne ($BOwnership + 1)) {
        throw "Recovered B ownership epoch transition is invalid."
    }
    if ([Math]::Abs([double]$FirstBRebound.position.x - $BX) -gt 0.000001) {
        throw "Recovered B duplicate replay changed durable position."
    }
    if ([int]$FirstBRebound.writer_count -ne 1) { throw "Recovered B did not become exactly one local writer after rebound." }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 15)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A2.Refresh(); $B2.Refresh()
        if ($A2.HasExited -or $B2.HasExited) { throw "Authority process exited after simultaneous-outage recovery." }
    }
    if (-not $C.HasExited) { throw "Client timed out after simultaneous dual-authority recovery." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A2, $B2)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) {
            Start-Sleep -Milliseconds 50
            $Server.Refresh()
        }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $A1Log), (Get-Content -LiteralPath $A2Log)) | Set-Content -LiteralPath $ALog -Encoding UTF8
    @((Get-Content -LiteralPath $B1Log), (Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) {
        throw "Base SM0 convergence failed after simultaneous dual-authority outage/restart."
    }

    $EA1 = @(Get-H32Events $A1Log)
    $EA2 = @(Get-H32Events $A2Log)
    $EB1 = @(Get-H32Events $B1Log)
    $EB2 = @(Get-H32Events $B2Log)
    $AllAuthorityEvents = @($EA1) + @($EA2) + @($EB1) + @($EB2)
    if (@($AllAuthorityEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) {
        throw "Invariant violation observed in H3.2 authority logs."
    }
    if (@($EA2 | Where-Object { $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $TransferId }).Count -lt 1) {
        throw "Recovered A did not idempotently finish historical source tracking."
    }
    if (@($EB2 | Where-Object { $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and [int]$_.last_input_sequence -eq $BSequence }).Count -lt 1) {
        throw "Recovered B duplicate ACK was not made durable."
    }

    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) {
        throw "Client H3.2 total-outage evidence failed."
    }

    $Crossings = @(Get-H32Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" } | Sort-Object { [int]$_.handoff_index })
    if ($Crossings.Count -ne $Handoffs) { throw "Expected $Handoffs completed crossings, got $($Crossings.Count)." }
    for ($Index = 0; $Index -lt $Crossings.Count; $Index++) {
        $ExpectedHandoff = $Index + 1
        $ExpectedEpoch = $ExpectedHandoff + 1
        if ([int]$Crossings[$Index].handoff_index -ne $ExpectedHandoff) { throw "Crossing index sequence is not contiguous." }
        if ([int]$Crossings[$Index].directory.authority_epoch -ne $ExpectedEpoch) {
            throw "Directory epoch is not monotonic at crossing $ExpectedHandoff; expected $ExpectedEpoch."
        }
    }
    $FinalDirectoryEpoch = [int]$Crossings[-1].directory.authority_epoch

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h32_dual_authority_outage_summary.v1"
        result = "PASS"
        git_head = $Head
        client_pid = $C.Id
        transfer_id = $TransferId
        outage_after_crossing = 1
        killed_a_pid = $A1Pid
        killed_b_pid = $B1Pid
        restarted_a_pid = $A2.Id
        restarted_b_pid = $B2.Id
        kill_request_gap_ms = $KillRequestGapMs
        a_retired_generation = $AGeneration
        b_active_generation = $BGeneration
        b_durable_input_sequence = $BSequence
        b_durable_position_x = $BX
        b_previous_ownership_epoch = $BOwnership
        b_recovered_ownership_epoch = [int]$FirstBRebound.ownership_epoch
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_epoch = $FinalDirectoryEpoch
        identity_changes = [int]$Result.identity_changes
        a_recovery_snapshot = $ASnapshotRecord.path
        b_recovery_snapshot = $BSnapshotRecord.path
        logs = $LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H3.2 simultaneous dual-authority total-outage recovery: PASS" -ForegroundColor Green
    Write-Host "  same client PID      : $($C.Id)"
    Write-Host "  outage after crossing: A -> B (#1)"
    Write-Host "  killed A PID         : $A1Pid"
    Write-Host "  killed B PID         : $B1Pid"
    Write-Host "  restarted A PID      : $($A2.Id)"
    Write-Host "  restarted B PID      : $($B2.Id)"
    Write-Host "  kill request gap     : ${KillRequestGapMs} ms"
    Write-Host "  A retired generation : $AGeneration"
    Write-Host "  B active gen/seq/x   : $BGeneration / $BSequence / $BX"
    Write-Host "  B ownership epoch    : $BOwnership -> $($FirstBRebound.ownership_epoch)"
    Write-Host "  handoffs             : $Handoffs / $Handoffs"
    Write-Host "  final directory epoch: $FinalDirectoryEpoch"
    Write-Host "  identity changes     : 0"
    Write-Host "  logs                 : $LogDir"
    Write-Host "  summary              : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H3.2 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C, $A1, $A2, $B1, $B2)) {
        if ($null -ne $Process) {
            try {
                $Process.Refresh()
                if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
            }
            catch {}
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
                    Write-Host "[SM0-H3.2] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H3.2 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
