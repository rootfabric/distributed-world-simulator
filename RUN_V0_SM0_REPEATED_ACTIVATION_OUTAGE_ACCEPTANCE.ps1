[CmdletBinding()]
param(
    [ValidateRange(2, 12)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(60, 900)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$FaultProfile = "h4-repeated-activation-dual-outage-v1"
if ($Final) {
    $Handoffs = 6
    if ($TimeoutSeconds -lt 600) { $TimeoutSeconds = 600 }
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-H4.1 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0SeamlessH41"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-H41Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Stop-H41 {
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            foreach ($Record in @($State.processes)) {
                if (Test-H41Alive ([int]$Record.pid)) {
                    Stop-Process -Id ([int]$Record.pid) -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {}
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    }
}

if ($Stop) { Stop-H41; exit 0 }
if ($Restart) { Stop-H41 }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-H4.1 requires a clean worktree:`n$($StatusBefore -join "`n")"
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
Write-Host "[SM0-H4.1] Running healthy preflight before repeated alternating outages..."
& $BaseRunner @Preflight
if ($LASTEXITCODE -ne 0) { throw "SM0-H4.1 healthy preflight failed." }

function Invoke-H41CompileCheck([string]$ScriptPath) {
    Write-Host "[SM0-H4.1] Compile check: $ScriptPath"
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
    if ($Code -ne 0) { throw "SM0-H4.1 compile check failed: $ScriptPath (exit $Code)" }
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
)) { Invoke-H41CompileCheck $ScriptPath }

function Invoke-H41Regression([string]$Label, [string]$ScriptPath) {
    Write-Host "[SM0-H4.1] Running $Label..."
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
    if ($Code -ne 0) { throw "SM0-H4.1 regression failed: $Label (exit $Code)" }
}

Invoke-H41Regression "transaction recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd"
Invoke-H41Regression "active-owner recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
Invoke-H41Regression "source-retire recovery regression" "res://tests/runtime/seamless/sm0/test_sm0_source_retire_recovery.gd"

function Test-H41PortFree([int]$Port) {
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

function Wait-H41Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $Deadline) {
        $AllFree = $true
        foreach ($Port in $Ports) {
            if (-not (Test-H41PortFree $Port)) { $AllFree = $false; break }
        }
        if ($AllFree) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

function Quote-H41([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$HarnessLog = Join-Path $LogDir "harness.log"
$ALog = Join-Path $LogDir "server-a.log"
$BLog = Join-Path $LogDir "server-b.log"
$CLog = Join-Path $LogDir "client.log"
$CResult = Join-Path $LogDir "client-result.json"
$StopFile = Join-Path $LogDir "stop.flag"
$SummaryPath = Join-Path $LogDir "h41-summary.json"

function Write-H41Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

function Start-H41Server([string]$AuthorityLetter, [string]$Role, [string]$Log) {
    if ($AuthorityLetter -eq "A") {
        $AuthorityId = "authority/sm0/a"; $ZoneId = "zone/earth/sm0/west"
        $GameplayPort = 24580; $ControlPort = 24680; $PeerControlPort = 24681
    }
    elseif ($AuthorityLetter -eq "B") {
        $AuthorityId = "authority/sm0/b"; $ZoneId = "zone/earth/sm0/east"
        $GameplayPort = 24581; $ControlPort = 24681; $PeerControlPort = 24680
    }
    else { throw "Unknown authority letter: $AuthorityLetter" }

    $UserArgs = @(
        "--authority-id=$AuthorityId", "--zone-id=$ZoneId",
        "--gameplay-port=$GameplayPort", "--control-port=$ControlPort", "--peer-control-port=$PeerControlPort",
        "--stop-file=$StopFile", "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )
    $Args = @(
        "--headless", "--path", (Quote-H41 $ProjectRoot),
        "--log-file", (Quote-H41 $Log),
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
    Write-H41Log "$Role started PID=$($Process.Id) log=$Log"
    return $Process
}

function Start-H41Client {
    $UserArgs = @(
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--handoffs=$Handoffs", "--timeout-ms=$($TimeoutSeconds*1000)", "--result-file=$CResult"
    )
    $Args = @(
        "--headless", "--path", (Quote-H41 $ProjectRoot),
        "--log-file", (Quote-H41 $CLog),
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
    Write-H41Log "client started PID=$($Process.Id) log=$CLog"
    return $Process
}

function Wait-H41Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Get-H41Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @($Events) }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') { $Events += ($Matches[1] | ConvertFrom-Json) }
    }
    return @($Events)
}

function Get-H41Crossings {
    return @(Get-H41Events $CLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" })
}

function Wait-H41CrossingCount([int]$Expected, [System.Diagnostics.Process]$Client, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Count = @(Get-H41Crossings).Count
        if ($Count -ge $Expected) { return }
        $Client.Refresh()
        if ($Client.HasExited -and $Count -lt $Expected) { throw "Client exited before crossing count $Expected; observed $Count." }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for crossing count $Expected."
}

function Get-H41Snapshot([string]$AuthorityLeaf, [int]$Generation) {
    $Path = Join-Path (Join-Path $RecoveryRoot $AuthorityLeaf) ("recovery-{0:d8}.json" -f $Generation)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Recovery snapshot is missing: $Path" }
    return [ordered]@{ path = $Path; value = (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
}

function Save-H41State([System.Diagnostics.Process]$A, [System.Diagnostics.Process]$B, [System.Diagnostics.Process]$Client) {
    $Processes = @()
    if ($null -ne $A) { $Processes += [ordered]@{ role = "server-a"; pid = $A.Id } }
    if ($null -ne $B) { $Processes += [ordered]@{ role = "server-b"; pid = $B.Id } }
    if ($null -ne $Client) { $Processes += [ordered]@{ role = "client"; pid = $Client.Id } }
    [ordered]@{
        schema = "distributed_world_simulator.sm0_h41_launcher_state.v1"
        project_root = $ProjectRoot
        git_head = $Head
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        processes = $Processes
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

$A = $null; $B = $null; $C = $null; $Exit = 1
$ASegmentLogs = New-Object System.Collections.Generic.List[string]
$BSegmentLogs = New-Object System.Collections.Generic.List[string]
$Cycles = New-Object System.Collections.Generic.List[object]
try {
    foreach ($Port in @(24580,24581,24680,24681,24780)) {
        if (-not (Test-H41PortFree $Port)) { throw "UDP port $Port is already in use." }
    }

    Write-H41Log "SM0-H4.1 start HEAD=$Head handoffs=$Handoffs outages=$Handoffs profile=$FaultProfile targets=B,A,..."

    $AInitialLog = Join-Path $LogDir "server-a-cycle00.log"
    $BInitialLog = Join-Path $LogDir "server-b-cycle00.log"
    $A = Start-H41Server "A" "server-a-cycle00" $AInitialLog
    $B = Start-H41Server "B" "server-b-cycle00" $BInitialLog
    $ASegmentLogs.Add($AInitialLog)
    $BSegmentLogs.Add($BInitialLog)
    Save-H41State $A $B $null

    Wait-H41Marker $AInitialLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-H41Marker $BInitialLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B 20
    Wait-H41Marker $AInitialLog '"event":"SM0_RECOVERY_ENABLED"' $A 20
    Wait-H41Marker $BInitialLog '"event":"SM0_RECOVERY_ENABLED"' $B 20
    Wait-H41Marker $AInitialLog '"event":"SM0_FAULT_PROFILE_ENABLED"' $A 20
    Wait-H41Marker $BInitialLog '"event":"SM0_FAULT_PROFILE_ENABLED"' $B 20

    $C = Start-H41Client
    $ClientPid = $C.Id
    Save-H41State $A $B $C

    $CurrentALog = $AInitialLog
    $CurrentBLog = $BInitialLog
    $SeenTransfers = @{}

    for ($Cycle = 1; $Cycle -le $Handoffs; $Cycle++) {
        $TargetLetter = if (($Cycle % 2) -eq 1) { "B" } else { "A" }
        $SourceLetter = if ($TargetLetter -eq "B") { "A" } else { "B" }
        $TargetAuthorityId = if ($TargetLetter -eq "B") { "authority/sm0/b" } else { "authority/sm0/a" }
        $SourceAuthorityId = if ($SourceLetter -eq "A") { "authority/sm0/a" } else { "authority/sm0/b" }
        $TargetProcess = if ($TargetLetter -eq "A") { $A } else { $B }
        $SourceProcess = if ($SourceLetter -eq "A") { $A } else { $B }
        $TargetLog = if ($TargetLetter -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($SourceLetter -eq "A") { $CurrentALog } else { $CurrentBLog }

        Wait-H41Marker $TargetLog '"crash_point":"REPEATED_DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK"' $TargetProcess 45
        Wait-H41Marker $SourceLog '"event":"SM0_SOURCE_TRANSFER_COMPLETE"' $SourceProcess 25

        $TargetEvents = @(Get-H41Events $TargetLog)
        $SourceEvents = @(Get-H41Events $SourceLog)
        $ClientBefore = @(Get-H41Crossings)
        if ($ClientBefore.Count -ne ($Cycle - 1)) {
            throw "Cycle $Cycle expected $($Cycle - 1) completed crossings before outage, got $($ClientBefore.Count)."
        }

        $CrashEvents = @($TargetEvents | Where-Object {
            $_.event -eq "SM0_H4_CRASH_POINT" -and $_.crash_point -eq "REPEATED_DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK"
        })
        if ($CrashEvents.Count -ne 1) { throw "Cycle $Cycle expected exactly one H4 crash point, got $($CrashEvents.Count)." }
        $Crash = $CrashEvents[0]
        $TransferId = [string]$Crash.transfer_id
        $TargetGeneration = [int]$Crash.recovery_generation
        if ([string]::IsNullOrWhiteSpace($TransferId) -or $TargetGeneration -lt 1) { throw "Cycle $Cycle invalid crash metadata." }
        if ([string]$Crash.target_authority_id -ne $TargetAuthorityId) {
            throw "Cycle $Cycle target authority mismatch: expected $TargetAuthorityId got $($Crash.target_authority_id)."
        }
        if ($SeenTransfers.ContainsKey($TransferId)) { throw "Cycle $Cycle reused transfer id $TransferId." }
        $SeenTransfers[$TransferId] = $true

        $TargetCommit = @($TargetEvents | Where-Object {
            $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
        })
        if ($TargetCommit.Count -ne 1) { throw "Cycle $Cycle expected one fresh target commit before outage." }
        $TargetActivated = @($TargetEvents | Where-Object {
            $_.event -eq "SM0_TARGET_ACTIVATED" -and [string]$_.transfer_id -eq $TransferId
        })
        if ($TargetActivated.Count -lt 1) { throw "Cycle $Cycle target was not activated before outage." }
        $ActiveDurable = @($TargetEvents | Where-Object {
            $_.event -eq "SM0_ACTIVE_OWNER_ACK_DURABLE" -and $_.message_type -eq "ACTIVATE_ACK" -and [int]$_.generation -eq $TargetGeneration
        })
        if ($ActiveDurable.Count -lt 1) { throw "Cycle $Cycle ACTIVE_OWNER durability evidence missing." }
        $Suppressed = @($TargetEvents | Where-Object {
            $_.event -eq "SM0_H4_TARGET_SEND_SUPPRESSED" -and $_.message_type -eq "ACTIVATE_ACK" -and [string]$_.transfer_id -eq $TransferId
        })
        if ($Suppressed.Count -ne 1) { throw "Cycle $Cycle ACTIVATE_ACK suppression evidence missing." }

        $SourceComplete = @($SourceEvents | Where-Object {
            $_.event -eq "SM0_SOURCE_TRANSFER_COMPLETE" -and [string]$_.transfer_id -eq $TransferId
        })
        if ($SourceComplete.Count -ne 1) { throw "Cycle $Cycle source transfer was not completed before outage." }
        $SourcePersisted = @($SourceEvents | Where-Object {
            $_.event -eq "SM0_RECOVERY_SNAPSHOT_PERSISTED" -and $_.phase -eq "SOURCE_RETIRED" -and [string]$_.transfer_id -eq $TransferId
        })
        if ($SourcePersisted.Count -ne 1) { throw "Cycle $Cycle durable SOURCE_RETIRED checkpoint missing." }
        $SourceGeneration = [int]$SourcePersisted[0].generation

        $TargetLeaf = if ($TargetLetter -eq "A") { "authority-a" } else { "authority-b" }
        $SourceLeaf = if ($SourceLetter -eq "A") { "authority-a" } else { "authority-b" }
        $TargetSnapshotRecord = Get-H41Snapshot $TargetLeaf $TargetGeneration
        $TargetSnapshot = $TargetSnapshotRecord.value
        if ([string]$TargetSnapshot.phase -ne "ACTIVE_OWNER") { throw "Cycle $Cycle target snapshot is not ACTIVE_OWNER." }
        if ([string]$TargetSnapshot.directory.owner_authority_id -ne $TargetAuthorityId) { throw "Cycle $Cycle target snapshot owner mismatch." }
        $CommittedProperty = $TargetSnapshot.committed_transfers.PSObject.Properties[$TransferId]
        if ($null -eq $CommittedProperty) { throw "Cycle $Cycle ACTIVE_OWNER snapshot lost committed transfer metadata." }

        $SourceSnapshotRecord = Get-H41Snapshot $SourceLeaf $SourceGeneration
        $SourceSnapshot = $SourceSnapshotRecord.value
        if ([string]$SourceSnapshot.phase -ne "SOURCE_RETIRED" -or [string]$SourceSnapshot.transfer_id -ne $TransferId) {
            throw "Cycle $Cycle source snapshot does not match SOURCE_RETIRED transfer."
        }
        if ([string]$SourceSnapshot.directory.owner_authority_id -ne $TargetAuthorityId) { throw "Cycle $Cycle source durable directory does not point to target." }

        $OldAPid = $A.Id; $OldBPid = $B.Id
        $TargetKillRequestMs = [Environment]::TickCount64
        Stop-Process -Id $TargetProcess.Id -Force -ErrorAction Stop
        $SourceKillRequestMs = [Environment]::TickCount64
        Stop-Process -Id $SourceProcess.Id -Force -ErrorAction Stop
        $KillGapMs = [Math]::Abs([long]$SourceKillRequestMs - [long]$TargetKillRequestMs)
        if ($KillGapMs -gt 500) { throw "Cycle $Cycle kill request gap exceeded 500 ms: $KillGapMs" }
        try { $null = $TargetProcess.WaitForExit(5000) } catch {}
        try { $null = $SourceProcess.WaitForExit(5000) } catch {}
        if ((Test-H41Alive $OldAPid) -or (Test-H41Alive $OldBPid)) { throw "Cycle $Cycle at least one authority survived total outage." }
        $C.Refresh()
        if ($C.HasExited) { throw "Cycle $Cycle client exited during zero-authority interval." }
        Wait-H41Ports @(24580,24581,24680,24681)
        Save-H41State $null $null $C
        Write-H41Log "Cycle ${Cycle}/${Handoffs} outage established transfer=${TransferId} target=$TargetLetter ACTIVE_OWNER gen=$TargetGeneration source=$SourceLetter SOURCE_RETIRED gen=$SourceGeneration oldA=$OldAPid oldB=$OldBPid gap=${KillGapMs}ms client=$ClientPid alive."

        $NewALog = Join-Path $LogDir ("server-a-cycle{0:d2}.log" -f $Cycle)
        $NewBLog = Join-Path $LogDir ("server-b-cycle{0:d2}.log" -f $Cycle)
        if ($TargetLetter -eq "A") {
            $A = Start-H41Server "A" "server-a-cycle$Cycle-target-recovery" $NewALog
            $B = Start-H41Server "B" "server-b-cycle$Cycle-source-recovery" $NewBLog
        }
        else {
            $B = Start-H41Server "B" "server-b-cycle$Cycle-target-recovery" $NewBLog
            $A = Start-H41Server "A" "server-a-cycle$Cycle-source-recovery" $NewALog
        }
        if ($A.Id -eq $OldAPid -or $B.Id -eq $OldBPid) { throw "Cycle $Cycle recovered authority unexpectedly reused its immediately crashed PID." }
        $ASegmentLogs.Add($NewALog)
        $BSegmentLogs.Add($NewBLog)
        $CurrentALog = $NewALog
        $CurrentBLog = $NewBLog
        Save-H41State $A $B $C

        $RecoveredTarget = if ($TargetLetter -eq "A") { $A } else { $B }
        $RecoveredSource = if ($SourceLetter -eq "A") { $A } else { $B }
        $RecoveredTargetLog = if ($TargetLetter -eq "A") { $NewALog } else { $NewBLog }
        $RecoveredSourceLog = if ($SourceLetter -eq "A") { $NewALog } else { $NewBLog }

        Wait-H41Marker $RecoveredTargetLog '"event":"SM0_RECOVERY_ACTIVE_OWNER_PENDING"' $RecoveredTarget 25
        Wait-H41Marker $RecoveredSourceLog '"event":"SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME"' $RecoveredSource 25
        Wait-H41Marker $RecoveredTargetLog '"event":"SM0_RECOVERY_SESSION_REBOUND"' $RecoveredTarget 45
        Wait-H41CrossingCount $Cycle $C 45

        $RecoveredTargetEvents = @(Get-H41Events $RecoveredTargetLog)
        $RecoveredSourceEvents = @(Get-H41Events $RecoveredSourceLog)
        $RestoredTarget = @($RecoveredTargetEvents | Where-Object {
            $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "ACTIVE_OWNER" -and [int]$_.generation -eq $TargetGeneration
        })
        if ($RestoredTarget.Count -ne 1) { throw "Cycle $Cycle target did not restore exact ACTIVE_OWNER generation." }
        $RestoredSource = @($RecoveredSourceEvents | Where-Object {
            $_.event -eq "SM0_RECOVERY_RESTORED" -and $_.phase -eq "SOURCE_RETIRED" -and [int]$_.generation -eq $SourceGeneration -and [string]$_.transfer_id -eq $TransferId
        })
        if ($RestoredSource.Count -ne 1 -or [int]$RestoredSource[0].writer_count -ne 0) {
            throw "Cycle $Cycle source did not restore exact retired non-writer state."
        }
        if (@($RecoveredTargetEvents | Where-Object {
            $_.event -eq "SM0_TARGET_AUTHORITY_COMMITTED" -and [string]$_.transfer_id -eq $TransferId
        }).Count -ne 0) { throw "Cycle $Cycle recovery created duplicate target commit/import." }
        if ((Select-String -LiteralPath $RecoveredTargetLog,$RecoveredSourceLog -SimpleMatch "SM0_COMMIT_WITHOUT_PREPARE" -Quiet -ErrorAction SilentlyContinue)) {
            throw "Cycle $Cycle recovery hit SM0_COMMIT_WITHOUT_PREPARE."
        }

        $CrossingsNow = @(Get-H41Crossings)
        if ($CrossingsNow.Count -ne $Cycle) { throw "Cycle $Cycle crossing count advanced by more than one: $($CrossingsNow.Count)." }
        $Crossing = $CrossingsNow[$Cycle - 1]
        if ([int]$Crossing.handoff_index -ne $Cycle) { throw "Cycle $Cycle crossing index mismatch." }
        if ([string]$Crossing.transfer_id -ne $TransferId) { throw "Cycle $Cycle crossing transfer mismatch." }
        if ([string]$Crossing.authority_id -ne $TargetAuthorityId) { throw "Cycle $Cycle crossing target authority mismatch." }
        if ([int]$Crossing.directory.authority_epoch -ne ($Cycle + 1)) { throw "Cycle $Cycle directory epoch mismatch." }

        $Cycles.Add([ordered]@{
            cycle = $Cycle
            transfer_id = $TransferId
            source_authority_id = $SourceAuthorityId
            target_authority_id = $TargetAuthorityId
            old_a_pid = $OldAPid
            old_b_pid = $OldBPid
            restarted_a_pid = $A.Id
            restarted_b_pid = $B.Id
            kill_request_gap_ms = $KillGapMs
            source_retired_generation = $SourceGeneration
            target_active_owner_generation = $TargetGeneration
            directory_epoch = [int]$Crossing.directory.authority_epoch
        })
        Write-H41Log "Cycle ${Cycle}/${Handoffs} recovered: target=$TargetLetter restored ACTIVE_OWNER gen=$TargetGeneration, source=$SourceLetter restored SOURCE_RETIRED gen=$SourceGeneration, crossing #$Cycle completed exactly once."
    }

    $Deadline = (Get-Date).AddSeconds(20)
    while (-not $C.HasExited -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 50; $C.Refresh() }
    if (-not $C.HasExited) { throw "Client did not exit after completing all H4.1 handoffs." }

    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($A,$B)) {
        $StopDeadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $StopDeadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    $ACombined = New-Object System.Collections.Generic.List[string]
    foreach ($Path in $ASegmentLogs) { if (Test-Path -LiteralPath $Path) { foreach ($Line in Get-Content -LiteralPath $Path) { $ACombined.Add($Line) } } }
    $ACombined | Set-Content -LiteralPath $ALog -Encoding UTF8
    $BCombined = New-Object System.Collections.Generic.List[string]
    foreach ($Path in $BSegmentLogs) { if (Test-Path -LiteralPath $Path) { foreach ($Line in Get-Content -LiteralPath $Path) { $BCombined.Add($Line) } } }
    $BCombined | Set-Content -LiteralPath $BLog -Encoding UTF8

    & (Join-Path $ProjectRoot "ANALYZE_V0_SM0_LOGS.ps1") -LogDirectory $LogDir -ExpectedHandoffs $Handoffs
    if ($LASTEXITCODE -ne 0 -or $C.ExitCode -ne 0) { throw "Base SM0 convergence failed after H4.1 repeated outages." }

    $AllEvents = @(Get-H41Events $ALog) + @(Get-H41Events $BLog)
    if (@($AllEvents | Where-Object { $_.event -eq "SM0_INVARIANT_VIOLATION" }).Count -ne 0) {
        throw "Invariant violation observed in H4.1 authority logs."
    }
    $Result = Get-Content -LiteralPath $CResult -Raw | ConvertFrom-Json
    if ($Result.result -ne "PASS" -or [int]$Result.handoffs_completed -ne $Handoffs -or [int]$Result.identity_changes -ne 0) {
        throw "Client H4.1 evidence failed."
    }
    $Crossings = @(Get-H41Crossings)
    if ($Crossings.Count -ne $Handoffs) { throw "H4.1 crossing event count mismatch." }
    for ($Index = 0; $Index -lt $Crossings.Count; $Index++) {
        $ExpectedIndex = $Index + 1
        $ExpectedTarget = if (($ExpectedIndex % 2) -eq 1) { "authority/sm0/b" } else { "authority/sm0/a" }
        if ([int]$Crossings[$Index].handoff_index -ne $ExpectedIndex) { throw "Non-contiguous H4.1 crossing index at $ExpectedIndex." }
        if ([string]$Crossings[$Index].authority_id -ne $ExpectedTarget) { throw "H4.1 target alternation mismatch at crossing $ExpectedIndex." }
        if ([int]$Crossings[$Index].directory.authority_epoch -ne ($ExpectedIndex + 1)) { throw "H4.1 directory epoch mismatch at crossing $ExpectedIndex." }
    }
    $ExpectedEpoch = $Handoffs + 1
    if ([int]$Result.authority_epoch_end -ne $ExpectedEpoch) {
        throw "Final directory epoch mismatch: expected $ExpectedEpoch got $($Result.authority_epoch_end)"
    }

    [ordered]@{
        schema = "distributed_world_simulator.sm0_h41_repeated_alternating_outage_summary.v1"
        result = "PASS"
        git_head = $Head
        fault_profile = $FaultProfile
        client_pid = $ClientPid
        outages_completed = $Cycles.Count
        handoffs_completed = [int]$Result.handoffs_completed
        final_directory_epoch = [int]$Result.authority_epoch_end
        identity_changes = [int]$Result.identity_changes
        cycles = @($Cycles)
        logs = $LogDir
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-H4.1 repeated alternating activation-outage campaign: PASS" -ForegroundColor Green
    Write-Host "  same client PID       : $ClientPid"
    Write-Host "  outages               : $($Cycles.Count) / $Handoffs"
    Write-Host "  target sequence       : B,A alternating"
    Write-Host "  handoffs              : $Handoffs / $Handoffs"
    Write-Host "  final directory epoch : $($Result.authority_epoch_end)"
    Write-Host "  identity changes      : 0"
    Write-Host "  logs                  : $LogDir"
    Write-Host "  summary               : $SummaryPath"
    $Exit = 0
}
catch {
    Write-Error "SM0-H4.1 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $Exit = 1
}
finally {
    foreach ($Process in @($C,$A,$B)) {
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
                    Write-Host "[SM0-H4.1] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-H4.1 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $Exit
