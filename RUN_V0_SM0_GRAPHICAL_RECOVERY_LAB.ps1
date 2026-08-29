[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(0, 1000)][int]$RequireRecoveries = 0,
    [ValidateRange(250, 5000)][int]$PhaseHoldMs = 850,
    [ValidateRange(250, 5000)][int]$OutageHoldMs = 1100,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
$FaultProfile = "h4-recovery-of-recovery-same-transfer-v1"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-P2 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalRecoveryLab"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-P2Alive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Stop-P2RecordedSession {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return }
    try {
        $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        foreach ($Record in @($State.processes)) {
            $PidValue = [int]$Record.pid
            if ($PidValue -gt 0 -and (Test-P2Alive $PidValue)) {
                Stop-Process -Id $PidValue -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {}
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}

if ($Stop) {
    Stop-P2RecordedSession
    Write-Host "[SM0-P2] Graphical recovery lab stopped."
    exit 0
}
if ($Restart) { Stop-P2RecordedSession }
elseif (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    throw "An SM0-P2 graphical recovery session is recorded. Use -Restart or -Stop."
}

if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) { throw "Godot double console executable not found: $GodotConsole" }
if (-not (Test-Path -LiteralPath $GodotGraphical -PathType Leaf)) { throw "Godot double graphical executable not found: $GodotGraphical" }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-P2 requires a clean worktree:`n$($StatusBefore -join "`n")"
}
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$VersionText = (& $GodotConsole --version | Select-Object -First 1).Trim()
if ($VersionText -ne $ExpectedVersion) { throw "Unexpected Godot console version: $VersionText" }
$GraphicalVersionText = (& $GodotGraphical --version | Select-Object -First 1).Trim()
if ($GraphicalVersionText -ne $ExpectedVersion) { throw "Unexpected Godot graphical version: $GraphicalVersionText" }

function Invoke-P2Godot([string[]]$Arguments) {
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Output = @(& $GodotConsole @Arguments 2>&1)
        $Exit = $LASTEXITCODE
        foreach ($Line in $Output) { Write-Host $Line }
        return $Exit
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
}

foreach ($ScriptPath in @(
    "res://scripts/runtime/seamless/sm0/sm0_manual_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_graphical_handoff_lab.gd",
    "res://scripts/runtime/seamless/sm0/sm0_graphical_recovery_lab.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd",
    "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd"
)) {
    Write-Host "[SM0-P2] Compile check: $ScriptPath"
    $CompileExit = Invoke-P2Godot @("--headless", "--path", $ProjectRoot, "--check-only", "--script", $ScriptPath)
    if ($CompileExit -ne 0) { throw "SM0-P2 compile check failed: $ScriptPath (exit $CompileExit)" }
}
Write-Host "[SM0-P2] Running graphical recovery scene smoke..."
$SmokeExit = Invoke-P2Godot @("--headless", "--path", $ProjectRoot, "res://scenes/testing/sm0_graphical_recovery_lab.tscn", "--", "--smoke")
if ($SmokeExit -ne 0) { throw "SM0-P2 graphical recovery smoke failed (exit $SmokeExit)" }

function Test-P2PortFree([int]$Port) {
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

function Wait-P2Ports([int[]]$Ports) {
    $Deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $Deadline) {
        $AllFree = $true
        foreach ($Port in $Ports) {
            if (-not (Test-P2PortFree $Port)) { $AllFree = $false; break }
        }
        if ($AllFree) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for UDP ports: $($Ports -join ', ')"
}

foreach ($Port in @(24580,24581,24680,24681,24780)) {
    if (-not (Test-P2PortFree $Port)) { throw "UDP port $Port is already in use." }
}

function Quote-P2([string]$Value) { return '"' + $Value + '"' }

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
$RecoveryRoot = Join-Path $LogDir "recovery"
New-Item -ItemType Directory -Force -Path $RecoveryRoot | Out-Null
$ClientLog = Join-Path $LogDir "graphical-client.log"
$StatusFile = Join-Path $LogDir "recovery-status.json"
$HarnessLog = Join-Path $LogDir "supervisor.log"
$StopFile = Join-Path $LogDir "stop.flag"

function Write-P2Log([string]$Message) {
    $Line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss.fff"), $Message
    Write-Host $Line
    Add-Content -LiteralPath $HarnessLog -Value $Line -Encoding UTF8
}

$A = $null
$B = $null
$Client = $null
$CurrentALog = ""
$CurrentBLog = ""
$ExitCode = 1
$CompletedRecoveries = 0

function Get-P2Pid([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return 0 }
    try { $Process.Refresh(); if ($Process.HasExited) { return 0 } } catch { return 0 }
    return $Process.Id
}

function Save-P2State {
    $Processes = @()
    foreach ($Record in @(
        [ordered]@{ role = "server-a"; process = $A },
        [ordered]@{ role = "server-b"; process = $B },
        [ordered]@{ role = "graphical-client"; process = $Client }
    )) {
        $PidValue = Get-P2Pid $Record.process
        if ($PidValue -gt 0) { $Processes += [ordered]@{ role = $Record.role; pid = $PidValue } }
    }
    [ordered]@{
        schema = "distributed_world_simulator.sm0_p2_graphical_recovery_session.v1"
        git_head = $Head
        project_root = $ProjectRoot
        log_directory = $LogDir
        recovery_directory = $RecoveryRoot
        status_file = $StatusFile
        processes = $Processes
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Write-P2Status(
    [string]$Stage,
    [int]$Chain,
    [int]$Outage,
    [string]$TransferId,
    [string]$Source,
    [string]$Target,
    [string]$AState,
    [string]$APhase,
    [int]$AGeneration,
    [string]$BState,
    [string]$BPhase,
    [int]$BGeneration,
    [string]$Message
) {
    $Status = [ordered]@{
        schema = "distributed_world_simulator.sm0_p2_graphical_recovery_status.v1"
        stage = $Stage
        chain = $Chain
        outage = $Outage
        transfer_id = $TransferId
        source = $Source
        target = $Target
        server_a = [ordered]@{ state = $AState; pid = (Get-P2Pid $A); phase = $APhase; generation = $AGeneration }
        server_b = [ordered]@{ state = $BState; pid = (Get-P2Pid $B); phase = $BPhase; generation = $BGeneration }
        message = $Message
        updated_at = (Get-Date).ToString("o")
    }
    $Temp = "$StatusFile.tmp"
    $Status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Temp -Encoding UTF8
    Move-Item -LiteralPath $Temp -Destination $StatusFile -Force
}

function Start-P2Server([string]$Letter, [string]$Role, [string]$LogPath) {
    if ($Letter -eq "A") {
        $AuthorityId = "authority/sm0/a"; $ZoneId = "zone/earth/sm0/west"
        $GameplayPort = 24580; $ControlPort = 24680; $PeerControlPort = 24681
    }
    elseif ($Letter -eq "B") {
        $AuthorityId = "authority/sm0/b"; $ZoneId = "zone/earth/sm0/east"
        $GameplayPort = 24581; $ControlPort = 24681; $PeerControlPort = 24680
    }
    else { throw "Unknown authority letter: $Letter" }
    $Args = @(
        "--headless", "--path", (Quote-P2 $ProjectRoot),
        "--log-file", (Quote-P2 $LogPath),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--",
        "--authority-id=$AuthorityId", "--zone-id=$ZoneId",
        "--gameplay-port=$GameplayPort", "--control-port=$ControlPort", "--peer-control-port=$PeerControlPort",
        "--stop-file=$StopFile", "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"
    )
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotConsole -ArgumentList $Args -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-P2Log "$Role PID=$($Process.Id) log=$LogPath"
    return $Process
}

function Start-P2GraphicalClient {
    $Args = @(
        "--path", (Quote-P2 $ProjectRoot),
        "--log-file", (Quote-P2 $ClientLog),
        "res://scenes/testing/sm0_graphical_recovery_lab.tscn", "--",
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780",
        "--recovery-status-file=$(Quote-P2 $StatusFile)"
    )
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotGraphical -ArgumentList $Args -WorkingDirectory $ProjectRoot -PassThru
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-P2Log "graphical-client PID=$($Process.Id) log=$ClientLog"
    return $Process
}

function Get-P2Events([string]$Path) {
    $Events = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $Events }
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') {
            try { $Events += ($Matches[1] | ConvertFrom-Json) } catch {}
        }
    }
    return $Events
}

function Wait-P2SimpleMarker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

function Wait-P2Stage(
    [string]$Path,
    [string]$Stage,
    [System.Diagnostics.Process]$Process,
    [System.Diagnostics.Process]$GraphicalClient,
    [bool]$AllowClientClose,
    [int]$Seconds
) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $GraphicalClient.Refresh()
        if ($GraphicalClient.HasExited) {
            if ($AllowClientClose) { return $null }
            throw "Graphical client exited while waiting for H4.3 stage $Stage."
        }
        $Process.Refresh()
        if ($Process.HasExited) { throw "Authority PID=$($Process.Id) exited before H4.3 stage $Stage. Log: $Path" }
        $Matches = @(Get-P2Events $Path | Where-Object { $_.event -eq "SM0_H43_CRASH_POINT" -and [string]$_.stage -eq $Stage })
        if ($Matches.Count -gt 0) { return $Matches[-1] }
        Start-Sleep -Milliseconds 60
    }
    throw "Timeout waiting for H4.3 stage $Stage in $Path"
}

function Wait-P2EventForTransfer(
    [string]$Path,
    [string]$EventName,
    [string]$TransferId,
    [System.Diagnostics.Process]$Process,
    [int]$Seconds
) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "Authority PID=$($Process.Id) exited before $EventName. Log: $Path" }
        $Matches = @(Get-P2Events $Path | Where-Object { $_.event -eq $EventName -and [string]$_.transfer_id -eq $TransferId })
        if ($Matches.Count -gt 0) { return $Matches[-1] }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $EventName transfer=$TransferId in $Path"
}

function Get-P2CrossingCount {
    return @(Get-P2Events $ClientLog | Where-Object { $_.event -eq "SM0_CROSSING_COMPLETED" }).Count
}

function Wait-P2Crossing([int]$Expected, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Client.Refresh()
        if ($Client.HasExited) { throw "Graphical client exited before crossing $Expected completed." }
        if ((Get-P2CrossingCount) -ge $Expected) { return }
        Start-Sleep -Milliseconds 60
    }
    throw "Timeout waiting for graphical crossing $Expected."
}

function Stop-P2AuthorityPair([int]$Chain, [string]$Stage, [string]$TransferId, [string]$Source, [string]$Target, [string]$APhase, [int]$AGen, [string]$BPhase, [int]$BGen) {
    $OldA = $A.Id
    $OldB = $B.Id
    $First = [Environment]::TickCount64
    Stop-Process -Id $OldA -Force -ErrorAction Stop
    $Second = [Environment]::TickCount64
    Stop-Process -Id $OldB -Force -ErrorAction Stop
    $Gap = [Math]::Abs([long]$Second - [long]$First)
    if ($Gap -gt 500) { throw "Chain $Chain $Stage kill gap exceeded 500 ms: $Gap" }
    try { $null = $A.WaitForExit(5000) } catch {}
    try { $null = $B.WaitForExit(5000) } catch {}
    if ((Test-P2Alive $OldA) -or (Test-P2Alive $OldB)) { throw "Chain $Chain $Stage total outage failed; an authority survived." }
    $Client.Refresh()
    if ($Client.HasExited) { throw "Graphical client exited during chain $Chain $Stage outage." }
    Write-P2Status "OUTAGE" $Chain 0 $TransferId $Source $Target "DOWN" $APhase $AGen "DOWN" $BPhase $BGen "Both authority processes are down. Kill gap ${Gap}ms. Durable files remain canonical recovery source."
    Save-P2State
    Start-Sleep -Milliseconds $OutageHoldMs
    Wait-P2Ports @(24580,24581,24680,24681)
    return $Gap
}

function Start-P2RecoveredPair([int]$Segment, [string]$Target, [string]$StageLabel) {
    $NewALog = Join-Path $LogDir ("server-a-segment{0:d2}.log" -f $Segment)
    $NewBLog = Join-Path $LogDir ("server-b-segment{0:d2}.log" -f $Segment)
    if ($Target -eq "A") {
        $A = Start-P2Server "A" "server-a-$StageLabel-target" $NewALog
        $B = Start-P2Server "B" "server-b-$StageLabel-source" $NewBLog
    }
    else {
        $B = Start-P2Server "B" "server-b-$StageLabel-target" $NewBLog
        $A = Start-P2Server "A" "server-a-$StageLabel-source" $NewALog
    }
    $script:A = $A
    $script:B = $B
    $script:CurrentALog = $NewALog
    $script:CurrentBLog = $NewBLog
    Save-P2State
    return [ordered]@{ a_log = $NewALog; b_log = $NewBLog }
}

try {
    Write-P2Log "SM0-P2 start HEAD=$Head profile=$FaultProfile"
    $CurrentALog = Join-Path $LogDir "server-a-segment00.log"
    $CurrentBLog = Join-Path $LogDir "server-b-segment00.log"
    $A = Start-P2Server "A" "server-a-initial" $CurrentALog
    $B = Start-P2Server "B" "server-b-initial" $CurrentBLog
    Save-P2State
    Wait-P2SimpleMarker $CurrentALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $A 20
    Wait-P2SimpleMarker $CurrentBLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $B 20
    Wait-P2SimpleMarker $CurrentALog '"event":"SM0_H43_PROFILE_ENABLED"' $A 20
    Wait-P2SimpleMarker $CurrentBLog '"event":"SM0_H43_PROFILE_ENABLED"' $B 20

    Write-P2Status "READY" 1 0 "" "A" "B" "ONLINE" "ACTIVE_OWNER" 0 "ONLINE" "STANDBY" 0 "Hold D and cross x=0. One exact transfer will survive PREPARED, COMMITTED and ACTIVE total outages."
    $Client = Start-P2GraphicalClient
    Save-P2State

    Write-Host ""
    Write-Host "SM0-P2 Graphical Recovery Lab is running." -ForegroundColor Green
    Write-Host "  A / D : cross WEST <-> EAST"
    Write-Host "  W / S : move along boundary"
    Write-Host "  P2 HUD: server process state, durable phase/generation, exact transfer"
    Write-Host "  Each crossing triggers 3 visible total A+B outages, then completes exactly once."
    Write-Host "  Close graphical window to finish."
    Write-Host "  HEAD  : $Head"
    Write-Host "  logs  : $LogDir"
    Write-Host ""

    $Segment = 0
    $Chain = 1
    while ($true) {
        $Client.Refresh()
        if ($Client.HasExited) { break }
        $Target = if (($Chain % 2) -eq 1) { "B" } else { "A" }
        $Source = if ($Target -eq "B") { "A" } else { "B" }
        $SourceProcess = if ($Source -eq "A") { $A } else { $B }
        $TargetProcess = if ($Target -eq "A") { $A } else { $B }
        $SourceLog = if ($Source -eq "A") { $CurrentALog } else { $CurrentBLog }
        $TargetLog = if ($Target -eq "A") { $CurrentALog } else { $CurrentBLog }

        $Prepared = Wait-P2Stage $SourceLog "PREPARED" $SourceProcess $Client $true 86400
        if ($null -eq $Prepared) { break }
        $TransferId = [string]$Prepared.transfer_id
        if ([string]::IsNullOrWhiteSpace($TransferId)) { throw "Chain $Chain PREPARED transfer id is empty." }
        $SourceGeneration = [int]$Prepared.recovery_generation
        $PreparedDurable = Wait-P2EventForTransfer $TargetLog "SM0_TARGET_PREPARED_DURABLE" $TransferId $TargetProcess 20
        $PreparedGeneration = [int]$PreparedDurable.generation
        $AGen = if ($Source -eq "A") { $SourceGeneration } else { $PreparedGeneration }
        $BGen = if ($Source -eq "B") { $SourceGeneration } else { $PreparedGeneration }
        $APhase = if ($Source -eq "A") { "SOURCE_RETIRED" } else { "TARGET_PREPARED" }
        $BPhase = if ($Source -eq "B") { "SOURCE_RETIRED" } else { "TARGET_PREPARED" }
        Write-P2Status "PREPARED" $Chain 1 $TransferId $Source $Target "ONLINE" $APhase $AGen "ONLINE" $BPhase $BGen "Same T is durable on both sides. COMMIT/redirect are held before outage #1."
        Start-Sleep -Milliseconds $PhaseHoldMs
        $null = Stop-P2AuthorityPair $Chain "PREPARED" $TransferId $Source $Target $APhase $AGen $BPhase $BGen

        $Segment++
        $null = Start-P2RecoveredPair $Segment $Target "chain$Chain-prepared-recovery"
        Write-P2Status "RECOVERING" $Chain 1 $TransferId $Source $Target "RECOVERING" $APhase $AGen "RECOVERING" $BPhase $BGen "Restoring exact PREPARED/SOURCE_RETIRED durable pair."
        $TargetProcess = if ($Target -eq "A") { $A } else { $B }
        $SourceProcess = if ($Source -eq "A") { $A } else { $B }
        $TargetLog = if ($Target -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($Source -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-P2SimpleMarker $TargetLog '"event":"SM0_H43_PROFILE_ENABLED"' $TargetProcess 25
        Wait-P2SimpleMarker $SourceLog '"event":"SM0_H43_PROFILE_ENABLED"' $SourceProcess 25

        $Committed = Wait-P2Stage $TargetLog "COMMITTED" $TargetProcess $Client $false 40
        if ([string]$Committed.transfer_id -ne $TransferId) { throw "Chain $Chain COMMITTED changed transfer id." }
        $CommittedGeneration = [int]$Committed.recovery_generation
        $AGen = if ($Target -eq "A") { $CommittedGeneration } else { $SourceGeneration }
        $BGen = if ($Target -eq "B") { $CommittedGeneration } else { $SourceGeneration }
        $APhase = if ($Target -eq "A") { "TARGET_COMMITTED" } else { "SOURCE_RETIRED" }
        $BPhase = if ($Target -eq "B") { "TARGET_COMMITTED" } else { "SOURCE_RETIRED" }
        Write-P2Status "COMMITTED" $Chain 2 $TransferId $Source $Target "ONLINE" $APhase $AGen "ONLINE" $BPhase $BGen "Recovery advanced the SAME T to TARGET_COMMITTED. ACK is held before outage #2."
        Start-Sleep -Milliseconds $PhaseHoldMs
        $null = Stop-P2AuthorityPair $Chain "COMMITTED" $TransferId $Source $Target $APhase $AGen $BPhase $BGen

        $Segment++
        $null = Start-P2RecoveredPair $Segment $Target "chain$Chain-committed-recovery"
        Write-P2Status "RECOVERING" $Chain 2 $TransferId $Source $Target "RECOVERING" $APhase $AGen "RECOVERING" $BPhase $BGen "Restoring exact TARGET_COMMITTED/SOURCE_RETIRED pair."
        $TargetProcess = if ($Target -eq "A") { $A } else { $B }
        $SourceProcess = if ($Source -eq "A") { $A } else { $B }
        $TargetLog = if ($Target -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($Source -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-P2SimpleMarker $TargetLog '"event":"SM0_H43_PROFILE_ENABLED"' $TargetProcess 25
        Wait-P2SimpleMarker $SourceLog '"event":"SM0_H43_PROFILE_ENABLED"' $SourceProcess 25

        $Active = Wait-P2Stage $TargetLog "ACTIVE" $TargetProcess $Client $false 40
        if ([string]$Active.transfer_id -ne $TransferId) { throw "Chain $Chain ACTIVE changed transfer id." }
        $ActiveGeneration = [int]$Active.recovery_generation
        $AGen = if ($Target -eq "A") { $ActiveGeneration } else { $SourceGeneration }
        $BGen = if ($Target -eq "B") { $ActiveGeneration } else { $SourceGeneration }
        $APhase = if ($Target -eq "A") { "ACTIVE_OWNER" } else { "SOURCE_RETIRED" }
        $BPhase = if ($Target -eq "B") { "ACTIVE_OWNER" } else { "SOURCE_RETIRED" }
        Write-P2Status "ACTIVE" $Chain 3 $TransferId $Source $Target "ONLINE" $APhase $AGen "ONLINE" $BPhase $BGen "Recovery advanced the SAME T to ACTIVE_OWNER. ACTIVATE_ACK is held before outage #3."
        Start-Sleep -Milliseconds $PhaseHoldMs
        $null = Stop-P2AuthorityPair $Chain "ACTIVE" $TransferId $Source $Target $APhase $AGen $BPhase $BGen

        $Segment++
        $null = Start-P2RecoveredPair $Segment $Target "chain$Chain-active-recovery"
        Write-P2Status "RECOVERING" $Chain 3 $TransferId $Source $Target "RECOVERING" $APhase $AGen "RECOVERING" $BPhase $BGen "Terminal restore from ACTIVE_OWNER. Client stays alive and must complete this crossing exactly once."
        $TargetProcess = if ($Target -eq "A") { $A } else { $B }
        $SourceProcess = if ($Source -eq "A") { $A } else { $B }
        $TargetLog = if ($Target -eq "A") { $CurrentALog } else { $CurrentBLog }
        $SourceLog = if ($Source -eq "A") { $CurrentALog } else { $CurrentBLog }
        Wait-P2SimpleMarker $TargetLog '"event":"SM0_H43_PROFILE_ENABLED"' $TargetProcess 25
        Wait-P2SimpleMarker $SourceLog '"event":"SM0_H43_PROFILE_ENABLED"' $SourceProcess 25
        Wait-P2Crossing $Chain 35
        $CompletedRecoveries = $Chain
        Write-P2Status "COMPLETE" $Chain 3 $TransferId $Source $Target "ONLINE" $APhase $AGen "ONLINE" $BPhase $BGen "Crossing #$Chain completed exactly once after three total outages. Same graphical client survived."
        Write-P2Log "Chain $Chain complete transfer=$TransferId source=$Source target=$Target PREPARED=$PreparedGeneration COMMITTED=$CommittedGeneration ACTIVE=$ActiveGeneration crossing=$Chain."
        Start-Sleep -Milliseconds 1400

        $Chain++
        $NextTarget = if (($Chain % 2) -eq 1) { "B" } else { "A" }
        $NextSource = if ($NextTarget -eq "B") { "A" } else { "B" }
        $Direction = if ($NextTarget -eq "B") { "D / EAST" } else { "A / WEST" }
        Write-P2Status "READY" $Chain 0 "" $NextSource $NextTarget "ONLINE" "RECOVERED" 0 "ONLINE" "RECOVERED" 0 "Recovery chain complete. Hold $Direction to start the next opposite-direction chain."
    }

    if ($RequireRecoveries -gt 0 -and $CompletedRecoveries -lt $RequireRecoveries) {
        throw "Expected at least $RequireRecoveries completed graphical recovery chains, observed $CompletedRecoveries."
    }
    Write-P2Log "Graphical client closed normally; completed recovery chains=$CompletedRecoveries."
    $ExitCode = 0
}
catch {
    try {
        Write-P2Status "FAILED" ([Math]::Max(1, $CompletedRecoveries + 1)) 0 "" "-" "-" "UNKNOWN" "-" 0 "UNKNOWN" "-" 0 $_.Exception.Message
    } catch {}
    Write-Error "SM0-P2 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $ExitCode = 1
}
finally {
    foreach ($Process in @($Client, $A, $B)) {
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
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-P2 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "SM0-P2 graphical recovery lab finished." -ForegroundColor Green
    Write-Host "  completed recovery chains : $CompletedRecoveries"
    Write-Host "  HEAD                      : $Head"
    Write-Host "  logs                      : $LogDir"
}
exit $ExitCode
