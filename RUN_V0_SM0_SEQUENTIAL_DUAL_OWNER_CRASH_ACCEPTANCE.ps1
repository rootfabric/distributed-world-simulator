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
    throw "SM0-H3.1 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH31"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H31Alive([int]$PidValue) {
    try {
        Get-Process -Id $PidValue -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function Stop-H31 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H31Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H31; exit 0 }
if ($Restart) { Stop-H31 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H3.1 requires a clean worktree:`n$($StatusBefore -join "`n")"
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
Write-Host "[SM0-H3.1] Running healthy preflight before sequential dual-owner crash chain..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H3.1 healthy preflight failed." }

function Invoke-H31CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H3.1] Compile check: $ScriptPath"
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
    if ($Code -ne 0) { throw "SM0-H3.1 compile check failed: $ScriptPath (exit $Code)" }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
)) { Invoke-H31CompileCheck $ScriptPath }

Write-Host "[SM0-H3.1] Running shared active-owner durable replay regression..."
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
if ($RegressionCode -ne 0) { throw "SM0-H3.1 active owner recovery regression failed (exit $RegressionCode)." }

function Test-H31PortFree([int]$Port) {
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

function Wait-H31Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $Ok = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H31PortFree $Port)) { $Ok = $false; break }
        }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H31([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$A1Log = Join-Path $LogDir "server-a-crashed.log"
$A2Log = Join-Path $LogDir "server-a-restarted.log"
$ALog = Join-Path $LogDir "server-a.log"
$B1Log = Join-Path $LogDir "server-b-crashed.log"
$B2Log = Join-Path $LogDir "server-b-restarted.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h31-summary.json"

function Write-H31Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H31Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H31 $ProjectRoot),
        "--log-file", (Quote-H31 $Log),
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
    Write-H31Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H31Client([string[]]$UserArgs) {
    $Args = @(
        "--headless", "--path", (Quote-H31 $ProjectRoot),
        "--log-file", (Quote-H31 $CLog),
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
    Write-H31Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H31Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
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

function Get-H31Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @($Events) }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') {
            $Events += ($Matches[1] | ConvertFrom-Json)
        }
    }
    return @($Events)
}

function Get-H31Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Recovery snapshot is missing: $Path"
    }
    return [ordered]@{ path = $Path; value = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
}

function Assert-H31ActiveSnapshot($Snapshot, [string]$AuthorityId, [string]$ZoneId, [int]$Sequence, [double]$PositionX) {
    if ([string]$Snapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1") {
        throw "Unexpected recovery snapshot schema."
    }
    if ([string]$Snapshot.phase -ne "ACTIVE_OWNER") { throw "Recovery snapshot is not ACTIVE_OWNER." }
    if ([string]$Snapshot.authority_id -ne $AuthorityId -or [string]$Snapshot.zone_id -ne $ZoneId) {
        throw "Recovery snapshot authority/zone mismatch."
    }
    if ([string]$Snapshot.directory.owner_authority_id -ne $AuthorityId) {
        throw "Recovery snapshot directory owner mismatch: expected $AuthorityId"
    }
    if ([int]$Snapshot.source_transfer.last_input_sequence -ne $Sequence) {
        throw "Recovery snapshot input sequence does not match crash marker."
    }
    $Players = @($Snapshot.gameplay_state.players.players | Where-Object { $_.logical_player_id -eq "a" })
    if ($Players.Count -ne 1) { throw "Recovery snapshot does not contain exactly one player a." }
    $Player = $Players[0]
    if ([string]$Player.player_entity_id -ne "player/a") { throw "Durable player identity changed." }
    if ([bool]$Player.connected -or -not [string]::IsNullOrEmpty([string]$Player.transport_session_id)) {
        throw "Durable player unexpectedly contains a live transport session."
    }
    if ([int]$Player.last_input_sequence -ne $Sequence) { throw "Durable player input sequence mismatch." }
    if ([Math]::Abs([double]$Player.position.x - $PositionX) -gt 0.000001) {
        throw "Durable player position differs from crash marker."
    }
}

function Get-H31SingleCrash([object[]]$Events) {
    $Crash = @($Events | Where-Object {
        $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"
    })
    if ($Crash.Count -ne 1) { throw "Expected exactly one active-owner crash marker, got $($Crash.Count)." }
    return $Crash[0]
}

function Assert-H31Rebound([object[]]$Events, [int]$Generation, [int]$Sequence, [int]$Ownership, [double]$PositionX, [string]$AuthorityId) {
    $Restored = @($Events | Where-Object {
        $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $Generation
    })
    if ($Restored.Count -ne 1) { throw "$AuthorityId did not restore exact ACTIVE_OWNER generation $Generation." }
    if ([string]$Restored[0].directory.owner_authority_id -ne $AuthorityId) {
        throw "$AuthorityId restored directory owned by another authority."
    }
    $Pending = @($Events | Where-Object {
        $_.event -eq "SM0_RECOVERY_ACTIVE_OWNER_PENDING" -and [int]$_.generation -eq $Generation
    })
    if ($Pending.Count -lt 1) { throw "$AuthorityId did not enter ACTIVE_OWNER_PENDING." }
    $Rebound = @($Events | Where-Object { $_.event -eq "SM0_RECOVERY_ACTIVE_OWNER_REBOUND" })
    if ($Rebound.Count -lt 1) { throw "$AuthorityId did not rebind the client session." }
    $First = $Rebound[0]
    if (-not [bool]$First.duplicate_durable_input) { throw "$AuthorityId retry was not exact durable replay." }
    if ([int]$First.last_input_sequence -ne $Sequence) { throw "$AuthorityId rebound sequence mismatch." }
    if ([int]$First.previous_ownership_epoch -ne $Ownership -or [int]$First.ownership_epoch -ne ($Ownership + 1)) {
        throw "$AuthorityId ownership epoch transition is invalid."
    }
    if ([Math]::Abs([double]$First.position.x - $PositionX) -gt 0.000001) {
        throw "$AuthorityId duplicate replay changed durable position."
    }
    return $First
}

$A1 = $null
$A2 = $null
$B1 = $null
$B2 = $null
$C = $null
$Exit = 1

try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H31PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H31Log "SM0-H3.1 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile sequential=A-then-B settle_steps=1"

    $A1 = Start-H31Godot "server-a-first-crash" $A1Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--fault-profile=$CrashProfile", "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    $B1 = Start-H31Godot "server-b-second-crash" $B1Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--fault-profile=$CrashProfile", "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )

    $State = [ordered]@{
        schema = "distributed_world_simulator.sm0_h31_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = @(
            [ordered]@{ role = "server-a-first-crash"; pid = $A1.Id },
            [ordered]@{ role = "server-b-second-crash"; pid = $B1.Id }
        )
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H31Marker $A1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A1 20
    Wait-H31Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H31Marker $A1Log '"event":"SM0_RECOVERY_ENABLED"' $A1 20
    Wait-H31Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H31Marker $A1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $A1 20
    Wait-H31Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H31Client @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$Handoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult",
        "--post-handoff-settle-steps=1"
    )
    $State.processes += [ordered]@{ role = "client"; pid = $C.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    # Phase A: initial authority crashes after persisting the first active-owner MOVE and before ACK.
    Wait-H31Marker $A1Log '"crash_point":"ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"' $A1 30
    $A1Events = @(Get-H31Events $A1Log)
    $ACrash = Get-H31SingleCrash $A1Events
    $AGeneration = [int]$ACrash.recovery_generation
    $ASequence = [int]$ACrash.last_input_sequence
    $AOwnership = [int]$ACrash.ownership_epoch
    $AX = [double]$ACrash.position.x
    if ($AGeneration -lt 1 -or $ASequence -lt 1 -or $AX -ge 0.0) {
        throw "Invalid A crash boundary generation=$AGeneration sequence=$ASequence x=$AX"
    }
    if (@($A1Events | Where-Object { $_.event -eq "SM0_HANDOFF_BEGIN" }).Count -ne 0) {
        throw "A began handoff before H3.1 first active-owner crash."
    }
    if (@(Get-H31Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" }).Count -ne 0) {
        throw "H3.1 first crash happened after a crossing."
    }
    if (@($A1Events | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $AGeneration
    }).Count -ne 1) {
        throw "Exact A ACTIVE_OWNER generation was not persisted before crash marker."
    }
    $ASnapshotRecord = Get-H31Snapshot "authority-a" $AGeneration
    $ASnapshot = $ASnapshotRecord.value
    Assert-H31ActiveSnapshot $ASnapshot "authority/sm0/a" "zone/earth/sm0/west" $ASequence $AX
    if ([int]$ASnapshot.directory.authority_epoch -ne 1) { throw "Initial A crash did not preserve directory epoch 1." }

    $A1Pid = $A1.Id
    Write-H31Log "First durable active move on A generation=$AGeneration sequence=$ASequence x=$AX; force-killing A PID=$A1Pid before MOVE_ACK"
    Stop-Process -Id $A1Pid -Force -ErrorAction Stop
    try { $null = $A1.WaitForExit(5000) } catch {}
    if (Test-H31Alive $A1Pid) { throw "A PID=$A1Pid survived forced crash." }
    $B1.Refresh()
    if ($B1.HasExited) { throw "B exited while recovering first crash on A." }
    Wait-H31Ports @(24580,24680)

    $A2 = Start-H31Godot "server-a-recovered" $A2Log @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    if ($A2.Id -eq $A1Pid) { throw "Restarted A unexpectedly reused crashed PID $A1Pid." }
    $State.processes += [ordered]@{ role = "server-a-recovered"; pid = $A2.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H31Marker $A2Log '"event":"SM0_RECOVERY_RESTORED"' $A2 20
    Wait-H31Marker $A2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $A2 20
    Wait-H31Marker $A2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A2 20
    Wait-H31Marker $A2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_REBOUND"' $A2 30
    $A2Events = @(Get-H31Events $A2Log)
    $ARebound = Assert-H31Rebound $A2Events $AGeneration $ASequence $AOwnership $AX "authority/sm0/a"
    Write-H31Log "A recovered PID=$($A2.Id), generation=$AGeneration, duplicate input rebound; continuing same client session toward A -> B."

    # Phase B: after the same client completes A -> B, crash B on an interior EAST MOVE.
    Wait-H31Marker $CLog '"event":"SM0_CROSSING_COMPLETED"' $C 45
    $CrossingsBeforeB = @(Get-H31Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsBeforeB.Count -ne 1) { throw "H3.1 requires exactly one A -> B crossing before B crash phase." }
    $FirstCrossing = $CrossingsBeforeB[0]
    if ([int]$FirstCrossing.handoff_index -ne 1 -or [string]$FirstCrossing.authority_id -ne "authority/sm0/b" -or [string]$FirstCrossing.zone_id -ne "zone/earth/sm0/east") {
        throw "First crossing did not activate authority B."
    }
    if ([string]$FirstCrossing.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$FirstCrossing.directory.authority_epoch -lt 2) {
        throw "First crossing directory does not prove B ownership at epoch >= 2."
    }

    Wait-H31Marker $B1Log '"crash_point":"ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"' $B1 30
    $B1Events = @(Get-H31Events $B1Log)
    $BCrash = Get-H31SingleCrash $B1Events
    $BGeneration = [int]$BCrash.recovery_generation
    $BSequence = [int]$BCrash.last_input_sequence
    $BOwnership = [int]$BCrash.ownership_epoch
    $BX = [double]$BCrash.position.x
    if ($BGeneration -lt 1 -or $BSequence -le $ASequence -or $BX -le 0.0) {
        throw "Invalid B crash boundary generation=$BGeneration sequence=$BSequence x=$BX"
    }
    if (@($B1Events | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" }).Count -lt 1) {
        throw "B crash happened before target activation."
    }
    if (@($B1Events | Where-Object { $_.event -eq "SM0_HANDOFF_BEGIN" }).Count -ne 0) {
        throw "B began B -> A handoff before H3.1 second active-owner crash."
    }
    $CrossingsAtBCrash = @(Get-H31Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsAtBCrash.Count -ne 1) { throw "Second crash was not isolated between crossing #1 and crossing #2." }
    if (@($B1Events | Where-Object {
        $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $BGeneration
    }).Count -ne 1) {
        throw "Exact B ACTIVE_OWNER generation was not persisted before crash marker."
    }
    $BSnapshotRecord = Get-H31Snapshot "authority-b" $BGeneration
    $BSnapshot = $BSnapshotRecord.value
    Assert-H31ActiveSnapshot $BSnapshot "authority/sm0/b" "zone/earth/sm0/east" $BSequence $BX
    if ([int]$BSnapshot.directory.authority_epoch -lt 2) { throw "B active-owner snapshot has stale directory epoch." }

    $B1Pid = $B1.Id
    Write-H31Log "After A recovery and A -> B crossing, interior B move generation=$BGeneration sequence=$BSequence x=$BX; force-killing B PID=$B1Pid before MOVE_ACK"
    Stop-Process -Id $B1Pid -Force -ErrorAction Stop
    try { $null = $B1.WaitForExit(5000) } catch {}
    if (Test-H31Alive $B1Pid) { throw "B PID=$B1Pid survived forced crash." }
    $A2.Refresh()
    if ($A2.HasExited) { throw "Recovered A exited while recovering second crash on B." }
    Wait-H31Ports @(24581,24681)

    $B2 = Start-H31Godot "server-b-recovered" $B2Log @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680", "--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot", "--active-owner-recovery=1"
    )
    if ($B2.Id -eq $B1Pid) { throw "Restarted B unexpectedly reused crashed PID $B1Pid." }
    $State.processes += [ordered]@{ role = "server-b-recovered"; pid = $B2.Id }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H31Marker $B2Log '"event":"SM0_RECOVERY_RESTORED"' $B2 20
    Wait-H31Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $B2 20
    Wait-H31Marker $B2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B2 20
    Wait-H31Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_REBOUND"' $B2 30
    $B2Events = @(Get-H31Events $B2Log)
    $BRebound = Assert-H31Rebound $B2Events $BGeneration $BSequence $BOwnership $BX "authority/sm0/b"
    Write-H31Log "B recovered PID=$($B2.Id), generation=$BGeneration, duplicate input rebound; waiting for final convergence in the same client session."

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 15)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A2.Refresh(); $B2.Refresh()
        if ($A2.HasExited -or $B2.HasExited) {
            throw "Authority process exited after sequential recovery chain."
        }
    }
    if (-not $C.HasExited) { throw "Client timed out after sequential A+B recovery chain." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A2,$B2)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) {
            Start-Sleep -Milliseconds 50
            $Server.Refresh()
        }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $A1Log),(Get-Content -LiteralPath $A2Log)) | Set-Content -LiteralPath $ALog -Encoding UTF8
    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) {
        throw "Base SM0 convergence failed after sequential A+B crash/recovery."
    }

    $EA1 = @(Get-H31Events $A1Log)
    $EA2 = @(Get-H31Events $A2Log)
    $EB1 = @(Get-H31Events $B1Log)
    $EB2 = @(Get-H31Events $B2Log)
    $EC = @(Get-H31Events $CLog)
    $AllEvents = @($EA1) + @($EA2) + @($EB1) + @($EB2) + @($EC)
    if (@($AllEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) {
        throw "Invariant violation observed in H3.1 logs."
    }

    if (@($EA2 | Where-Object {
        $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and [int]$_.last_input_sequence -eq $ASequence
    }).Count -lt 1) {
        throw "Recovered A duplicate ACK was not made durable."
    }
    if (@($EB2 | Where-Object {
        $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and [int]$_.last_input_sequence -eq $BSequence
    }).Count -lt 1) {
        throw "Recovered B duplicate ACK was not made durable."
    }

    $Crossings = @($EC | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($Crossings.Count -ne $Handoffs) { throw "Expected $Handoffs completed crossings, got $($Crossings.Count)." }
    $PreviousEpoch = 0
    for ($Index = 0; $Index -lt $Crossings.Count; $Index++) {
        $ExpectedIndex = $Index + 1
        $Crossing = $Crossings[$Index]
        if ([int]$Crossing.handoff_index -ne $ExpectedIndex) { throw "Crossing index sequence is not contiguous." }
        $Epoch = [int]$Crossing.directory.authority_epoch
        if ($Epoch -le $PreviousEpoch) { throw "Directory authority epochs are not strictly increasing across crossings." }
        $PreviousEpoch = $Epoch
        if ([string]$Crossing.player.player_entity_id -ne "player/a") { throw "Player identity changed in crossing evidence." }
    }

    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) {
        throw "Client H3.1 sequential recovery evidence failed."
    }

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h31_sequential_dual_owner_summary.v1"
        result = "PASS"
        git_head = $Head
        crash_order = @("authority/sm0/a", "authority/sm0/b")
        client_process_id = $C.Id
        a = [ordered]@{
            crashed_pid = $A1Pid
            restarted_pid = $A2.Id
            generation = $AGeneration
            input_sequence = $ASequence
            position_x = $AX
            previous_ownership_epoch = $AOwnership
            recovered_ownership_epoch = [int]$ARebound.ownership_epoch
            snapshot = $ASnapshotRecord.path
        }
        b = [ordered]@{
            crashed_pid = $B1Pid
            restarted_pid = $B2.Id
            generation = $BGeneration
            input_sequence = $BSequence
            position_x = $BX
            directory_authority_epoch = [int]$BSnapshot.directory.authority_epoch
            previous_ownership_epoch = $BOwnership
            recovered_ownership_epoch = [int]$BRebound.ownership_epoch
            snapshot = $BSnapshotRecord.path
        }
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_authority_epoch = $PreviousEpoch
        identity_changes = [int]$Result.identity_changes
        logs = $LogDir
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H3.1 sequential dual-authority active-owner recovery: PASS" -ForegroundColor Green
    Write-Host "  same client PID      : $($C.Id)"
    Write-Host "  first crash          : A $A1Pid -> $($A2.Id)"
    Write-Host "  A generation/seq/x   : $AGeneration / $ASequence / $AX"
    Write-Host "  A ownership epoch    : $AOwnership -> $($ARebound.ownership_epoch)"
    Write-Host "  crossing #1          : A -> B"
    Write-Host "  second crash         : B $B1Pid -> $($B2.Id)"
    Write-Host "  B generation/seq/x   : $BGeneration / $BSequence / $BX"
    Write-Host "  B ownership epoch    : $BOwnership -> $($BRebound.ownership_epoch)"
    Write-Host "  handoffs             : $Handoffs / $Handoffs"
    Write-Host "  final directory epoch: $PreviousEpoch"
    Write-Host "  identity changes     : 0"
    Write-Host "  logs                 : $LogDir"
    Write-Host "  summary              : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H3.1 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A1,$A2,$B1,$B2)) {
        if ($null -ne $Process) {
            try {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                }
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
                    Write-Host "[SM0-H3.1] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H3.1 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
