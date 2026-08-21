[CmdletBinding()]
param(
    [ValidateRange(2, 100)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$CrashProfile = "h2-active-owner-crash-after-move-persist-v1"
if ($Final) { $Handoffs = 6; if ($TimeoutSeconds -lt 180) { $TimeoutSeconds = 180 } }
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) { throw "SM0-H2.5 must run under C:\distributed-world-simulator. Current: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot double console executable not found: $GodotExe" }

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH25"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H25Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}
function Stop-H25 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H25Alive ([int]$Record.pid)) { Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue }
            }
        } catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}
if ($Stop) { Stop-H25; exit 0 }
if ($Restart) { Stop-H25 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "SM0-H2.5 requires a clean worktree:`n$($StatusBefore -join "`n")" }
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate pre-existing UID sidecars." }
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$BaseRunner = Join-Path $ProjectRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
$Preflight = @{ Handoffs = 2; Restart = $true; ProjectRoot = $ProjectRoot; GodotExe = $GodotExe; TimeoutSeconds = 120 }
if ($AllowDirty) { $Preflight.AllowDirty = $true }
Write-Host "[SM0-H2.5] Running healthy preflight before handoff-target active-owner crash injection..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H2.5 healthy preflight failed." }

function Invoke-H25CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H2.5] Compile check: $ScriptPath"
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        $Code = $LASTEXITCODE
    }
    finally {
        if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    if ($Code -ne 0) { throw "SM0-H2.5 compile check failed: $ScriptPath (exit $Code)" }
}
foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_active_recovery_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
)) { Invoke-H25CompileCheck $ScriptPath }

Write-Host "[SM0-H2.5] Running shared active-owner durable replay regression..."
$OldRegression = $env:BREAKPOINT_RUNTIME_DISABLED; $HadRegression = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotExe --headless --path $ProjectRoot --script "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
    $RegressionCode = $LASTEXITCODE
}
finally {
    if ($HadRegression) { $env:BREAKPOINT_RUNTIME_DISABLED = $OldRegression } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}
if ($RegressionCode -ne 0) { throw "SM0-H2.5 active owner recovery regression failed (exit $RegressionCode)." }

function Test-H25PortFree([int]$Port) {
    $Udp = $null
    try {
        $Udp = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $Udp.Client.ExclusiveAddressUse = $true
        $Udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    } catch { return $false } finally { if ($null -ne $Udp) { $Udp.Dispose() } }
}
function Wait-H25Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $Ok = $true
        foreach ($Port in $Ports) { if (-not (Test-H25PortFree $Port)) { $Ok = $false; break } }
        if ($Ok) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}
function Quote-H25([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$ALog = Join-Path $LogDir "server-a.log"
$B1Log = Join-Path $LogDir "server-b-crashed.log"
$B2Log = Join-Path $LogDir "server-b-restarted.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h25-summary.json"
function Write-H25Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H25Godot([string]$Role, [string]$Log, [string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H25 $ProjectRoot), "--log-file", (Quote-H25 $Log), "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H25Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}
function Start-H25Client([string[]]$UserArgs) {
    $Args = @("--headless", "--path", (Quote-H25 $ProjectRoot), "--log-file", (Quote-H25 $CLog), "--script", "res://scripts/runtime/seamless/sm0/sm0_automated_client_process.gd", "--") + $UserArgs
    $Old = $env:BREAKPOINT_RUNTIME_DISABLED; $Had = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    try { $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $Process = Start-Process -FilePath $GodotExe -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru }
    finally { if ($Had) { $env:BREAKPOINT_RUNTIME_DISABLED = $Old } else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue } }
    Write-H25Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}
function Wait-H25Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}
function Get-H25Events([string]$Path) {
    $Events = @()
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Events += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Events)
}

$A = $null; $B1 = $null; $B2 = $null; $C = $null; $Exit = 1
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H25PortFree $Port)) { throw "UDP port $Port is already in use." }
    }
    Write-H25Log "SM0-H2.5 start HEAD=$Head handoffs=$Handoffs profile=$CrashProfile crash_authority=authority/sm0/b settle_steps=1"
    $A = Start-H25Godot "server-a" $ALog @(
        "--authority-id=authority/sm0/a","--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580","--control-port=24680","--peer-control-port=24681","--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot","--active-owner-recovery=1"
    )
    $B1 = Start-H25Godot "server-b-active-crash" $B1Log @(
        "--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile",
        "--fault-profile=$CrashProfile","--recovery-dir=$RecoveryRoot","--active-owner-recovery=1"
    )
    $State = [ordered]@{
        schema="distributed_world_simulator.sm0_h25_launcher_state.v1"; project_root=$ProjectRoot; git_head=$Head;
        log_directory=$LogDir; recovery_directory=$RecoveryRoot;
        processes=@([ordered]@{role="server-a";pid=$A.Id},[ordered]@{role="server-b-active-crash";pid=$B1.Id})
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H25Marker $ALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-H25Marker $B1Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B1 20
    Wait-H25Marker $ALog '"event":"SM0_RECOVERY_ENABLED"' $A 20
    Wait-H25Marker $B1Log '"event":"SM0_RECOVERY_ENABLED"' $B1 20
    Wait-H25Marker $B1Log '"event":"SM0_FAULT_PROFILE_ENABLED"' $B1 20

    $C = Start-H25Client @(
        "--server-host=127.0.0.1","--server-a-port=24580","--server-b-port=24581","--client-port=24780",
        "--handoffs=$Handoffs","--timeout-ms=$($TimeoutSeconds*1000)","--result-file=$CResult",
        "--post-handoff-settle-steps=1"
    )
    $State.processes += [ordered]@{role="client";pid=$C.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Wait-H25Marker $CLog '"event":"SM0_CROSSING_COMPLETED"' $C 30
    $CrossingsBeforeCrash = @(Get-H25Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsBeforeCrash.Count -lt 1) { throw "H2.5 requires A -> B crossing before target-owner crash." }
    $FirstCrossing = $CrossingsBeforeCrash[0]
    if ([int]$FirstCrossing.handoff_index -ne 1 -or [string]$FirstCrossing.authority_id -ne "authority/sm0/b" -or [string]$FirstCrossing.zone_id -ne "zone/earth/sm0/east") {
        throw "First crossing did not activate authority B as target owner."
    }
    if ([string]$FirstCrossing.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$FirstCrossing.directory.authority_epoch -lt 2) {
        throw "First crossing directory does not prove B ownership at epoch >= 2."
    }

    Wait-H25Marker $B1Log '"crash_point":"ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK"' $B1 30
    $B1BeforeCrash = @(Get-H25Events $B1Log)
    $Crash = @($B1BeforeCrash | Where-Object { $_.event -eq "SM0_H2_CRASH_POINT" -and $_.crash_point -eq "ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK" })
    if ($Crash.Count -ne 1) { throw "Expected one H2.5 crash point before kill, got $($Crash.Count)." }
    $CrashGeneration = [int]$Crash[0].recovery_generation
    $CrashSequence = [int]$Crash[0].last_input_sequence
    $CrashOwnership = [int]$Crash[0].ownership_epoch
    $CrashX = [double]$Crash[0].position.x
    if ($CrashGeneration -lt 1 -or $CrashSequence -lt 1) { throw "Invalid target-owner crash evidence generation=$CrashGeneration sequence=$CrashSequence" }
    if ($CrashX -le 0.0) { throw "H2.5 crash point is not inside B EAST zone: x=$CrashX" }
    if (@($B1BeforeCrash | Where-Object { $_.event -eq "SM0_TARGET_ACTIVATED" }).Count -lt 1) { throw "Authority B crash occurred before target activation." }
    if (@($B1BeforeCrash | Where-Object { $_.event -eq "SM0_HANDOFF_BEGIN" }).Count -ne 0) { throw "Authority B began B -> A handoff before H2.5 active-owner crash." }
    if (@($B1BeforeCrash | Where-Object { $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $CrashGeneration }).Count -ne 1) {
        throw "Exact B ACTIVE_OWNER generation was not persisted before crash marker."
    }
    $CrossingsAtCrash = @(Get-H25Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
    if ($CrossingsAtCrash.Count -ne 1 -or [string]$CrossingsAtCrash[0].authority_id -ne "authority/sm0/b") {
        throw "H2.5 requires exactly one completed A -> B crossing before active-owner crash."
    }

    $SnapshotPath = Join-Path (Join-Path $RecoveryRoot "authority-b") ("recovery-{0:d8}.json" -f $CrashGeneration)
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Persisted B active-owner snapshot is missing: $SnapshotPath" }
    $Snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
    if ($Snapshot.schema -ne "distributed_world_simulator.sm0_handoff_recovery_snapshot.v1" -or $Snapshot.phase -ne "ACTIVE_OWNER") { throw "B crash snapshot is not ACTIVE_OWNER." }
    if ([string]$Snapshot.authority_id -ne "authority/sm0/b" -or [string]$Snapshot.zone_id -ne "zone/earth/sm0/east") { throw "Crash snapshot is not owned by authority B." }
    if ([string]$Snapshot.directory.owner_authority_id -ne "authority/sm0/b" -or [int]$Snapshot.directory.authority_epoch -lt 2) { throw "Crash snapshot directory does not preserve B as current owner." }
    if ([int]$Snapshot.source_transfer.last_input_sequence -ne $CrashSequence -or [int]$Snapshot.source_transfer.ownership_epoch -ne $CrashOwnership) { throw "B active-owner metadata does not match crash marker." }
    $DurablePlayer = @($Snapshot.gameplay_state.players.players | Where-Object { $_.logical_player_id -eq "a" })
    if ($DurablePlayer.Count -ne 1) { throw "B crash snapshot does not contain exactly one durable player a." }
    if ([string]$DurablePlayer[0].player_entity_id -ne "player/a") { throw "B durable player identity changed." }
    if ([bool]$DurablePlayer[0].connected -or -not [string]::IsNullOrEmpty([string]$DurablePlayer[0].transport_session_id)) { throw "B durable player unexpectedly persisted a live transport session." }
    if ([int]$DurablePlayer[0].last_input_sequence -ne $CrashSequence -or [Math]::Abs([double]$DurablePlayer[0].position.x - $CrashX) -gt 0.000001) { throw "B durable movement does not match crash marker." }

    $CrashPid = $B1.Id
    Write-H25Log "A -> B handoff completed; interior EAST move durable generation=$CrashGeneration sequence=$CrashSequence x=$CrashX; force-killing B PID=$CrashPid before MOVE_ACK"
    Stop-Process -Id $CrashPid -Force -ErrorAction Stop
    try { $null = $B1.WaitForExit(5000) } catch {}
    if (Test-H25Alive $CrashPid) { throw "Target active owner B PID=$CrashPid survived forced crash." }
    $A.Refresh()
    if ($A.HasExited) { throw "Authority A exited while recovering crashed B." }
    Wait-H25Ports @(24581,24681)

    $B2 = Start-H25Godot "server-b-recovered" $B2Log @(
        "--authority-id=authority/sm0/b","--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581","--control-port=24681","--peer-control-port=24680","--stop-file=$StopFile",
        "--recovery-dir=$RecoveryRoot","--active-owner-recovery=1"
    )
    if ($B2.Id -eq $CrashPid) { throw "Restarted B unexpectedly reused crashed PID $CrashPid." }
    $State.processes += [ordered]@{role="server-b-recovered";pid=$B2.Id}
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Wait-H25Marker $B2Log '"event":"SM0_RECOVERY_RESTORED"' $B2 20
    Wait-H25Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $B2 20
    Wait-H25Marker $B2Log '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B2 20
    Wait-H25Marker $B2Log '"event":"SM0_RECOVERY_ACTIVE_OWNER_REBOUND"' $B2 30
    Write-H25Log "Restarted B restored post-handoff active-owner movement and rebound the outstanding client move; waiting for convergence."

    $B2RecoveryEvents = @(Get-H25Events $B2Log)
    $Restored = @($B2RecoveryEvents | Where-Object { $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $CrashGeneration })
    if ($Restored.Count -ne 1) { throw "Restarted B did not restore exact ACTIVE_OWNER generation." }
    if ([string]$Restored[0].directory.owner_authority_id -ne "authority/sm0/b") { throw "Restarted B restored a directory owned by another authority." }
    $Rebound = @($B2RecoveryEvents | Where-Object { $_.event -eq "SM0_RECOVERY_ACTIVE_OWNER_REBOUND" })
    if ($Rebound.Count -lt 1) { throw "Recovered B did not rebind client session." }
    $FirstRebound = $Rebound[0]
    if (-not [bool]$FirstRebound.duplicate_durable_input) { throw "Recovered B client input was not classified as exact durable retry." }
    if ([int]$FirstRebound.last_input_sequence -ne $CrashSequence) { throw "Recovered B sequence differs from crash sequence." }
    if ([int]$FirstRebound.previous_ownership_epoch -ne $CrashOwnership -or [int]$FirstRebound.ownership_epoch -ne ($CrashOwnership + 1)) { throw "Controlled B recovery ownership epoch transition is invalid." }
    if ([Math]::Abs([double]$FirstRebound.position.x - $CrashX) -gt 0.000001) { throw "Recovered duplicate movement changed B position." }

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds + 10)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 50
        $C.Refresh(); $A.Refresh(); $B2.Refresh()
        if ($A.HasExited -or $B2.HasExited) { throw "Authority process exited after B active-owner recovery." }
    }
    if (-not $C.HasExited) { throw "Client timed out after B active-owner recovery." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A,$B2)) {
        $StopDeadline=(Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date)-lt $StopDeadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    @((Get-Content -LiteralPath $B1Log),(Get-Content -LiteralPath $B2Log)) | Set-Content -LiteralPath $BLog -Encoding UTF8
    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after handoff-target B crash/restart." }

    $EA = @(Get-H25Events $ALog); $EB1 = @(Get-H25Events $B1Log); $EB2 = @(Get-H25Events $B2Log)
    $AllAuthorityEvents = @($EA) + @($EB1) + @($EB2)
    if (@($AllAuthorityEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) { throw "Invariant violation observed in H2.5 authority logs." }
    if (@($EB2 | Where-Object { $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and [int]$_.last_input_sequence -eq $CrashSequence }).Count -lt 1) { throw "Recovered B duplicate ACK was not itself made durable." }

    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) { throw "Client H2.5 target-owner recovery evidence failed." }

    [ordered]@{
        schema="distributed_world_simulator.sm0_h25_target_owner_summary.v1"; result="PASS"; git_head=$Head;
        crash_authority_id="authority/sm0/b"; crash_point="ACTIVE_OWNER_AFTER_MOVE_PERSIST_BEFORE_ACK";
        crossings_before_crash=$CrossingsAtCrash.Count; crash_generation=$CrashGeneration; crash_input_sequence=$CrashSequence;
        crash_position_x=$CrashX; crashed_owner_pid=$CrashPid; restarted_owner_pid=$B2.Id;
        crash_inside_target_zone=$true; directory_authority_epoch=[int]$Snapshot.directory.authority_epoch;
        previous_ownership_epoch=$CrashOwnership; recovered_ownership_epoch=[int]$FirstRebound.ownership_epoch;
        handoffs_completed=[int]$Result.handoffs_completed; identity_changes=[int]$Result.identity_changes;
        recovery_snapshot=$SnapshotPath; logs=$LogDir
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H2.5 handoff-target active owner recovery: PASS" -ForegroundColor Green
    Write-Host "  crash authority     : authority/sm0/b"
    Write-Host "  crossings before X : $($CrossingsAtCrash.Count)"
    Write-Host "  crashed PID         : $CrashPid"
    Write-Host "  restarted PID       : $($B2.Id)"
    Write-Host "  recovery generation : $CrashGeneration"
    Write-Host "  directory epoch     : $($Snapshot.directory.authority_epoch)"
    Write-Host "  durable input seq   : $CrashSequence"
    Write-Host "  durable position x  : $CrashX"
    Write-Host "  ownership epoch     : $CrashOwnership -> $($FirstRebound.ownership_epoch)"
    Write-Host "  handoffs            : $Handoffs / $Handoffs"
    Write-Host "  identity changes    : 0"
    Write-Host "  snapshot            : $SnapshotPath"
    Write-Host "  logs                : $LogDir"
    Write-Host "  summary             : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H2.5 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A,$B1,$B2)) {
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
                    Write-Host "[SM0-H2.5] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H2.5 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
