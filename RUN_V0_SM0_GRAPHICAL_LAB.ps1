[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(0, 1000)][int]$RequireHandoffs = 0,
    [string]$NetworkProfile = "",
    [ValidateRange(0, 10000)][int]$NetworkLatencyMs = 0,
    [ValidateRange(0, 5000)][int]$NetworkJitterMs = 0,
    [int]$NetworkSeed = 431,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-P1 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}

$P31NetworkProfile = "p31-controlled-latency-v1"
if (-not [string]::IsNullOrWhiteSpace($NetworkProfile)) {
    if ($NetworkProfile -ne $P31NetworkProfile) { throw "Unsupported SM0 graphical network profile: $NetworkProfile" }
    if ($NetworkLatencyMs -lt 1) { throw "SM0-P3.1 network profile requires NetworkLatencyMs >= 1." }
    if ($NetworkJitterMs -gt $NetworkLatencyMs) { throw "SM0-P3.1 NetworkJitterMs cannot exceed NetworkLatencyMs." }
}
elseif ($NetworkLatencyMs -ne 0 -or $NetworkJitterMs -ne 0) {
    throw "Network latency/jitter parameters require -NetworkProfile $P31NetworkProfile."
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$Root = Join-Path $LocalAppData "DistributedWorldSimulator\SM0GraphicalLab"
$StatePath = Join-Path $Root "session.json"
$LogsRoot = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null

function Test-Sm0ProcessAlive([int]$PidValue) {
    try { Get-Process -Id $PidValue -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Stop-Sm0GraphicalSession {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return }
    try {
        $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$State.stop_file)) {
            New-Item -ItemType File -Force -Path ([string]$State.stop_file) -ErrorAction SilentlyContinue | Out-Null
        }
        Start-Sleep -Milliseconds 350
        foreach ($Record in @($State.processes)) {
            $PidValue = [int]$Record.pid
            if (Test-Sm0ProcessAlive $PidValue) {
                Stop-Process -Id $PidValue -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}

if ($Stop) {
    Stop-Sm0GraphicalSession
    Write-Host "[SM0-P1] Graphical lab stopped."
    exit 0
}
if ($Restart) { Stop-Sm0GraphicalSession }
elseif (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    throw "An SM0-P1 graphical session is recorded. Use -Restart or -Stop."
}

if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) { throw "Godot double console executable not found: $GodotConsole" }
if (-not (Test-Path -LiteralPath $GodotGraphical -PathType Leaf)) { throw "Godot double graphical executable not found: $GodotGraphical" }

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-P1 requires a clean worktree:`n$($StatusBefore -join "`n")"
}
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

function Invoke-Sm0P1Godot {
    param([string[]]$Arguments)
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

$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$VersionText = (& $GodotConsole --version | Select-Object -First 1).Trim()
if ($VersionText -ne $ExpectedVersion) { throw "Unexpected Godot console version: $VersionText" }
$GraphicalVersionText = (& $GodotGraphical --version | Select-Object -First 1).Trim()
if ($GraphicalVersionText -ne $ExpectedVersion) { throw "Unexpected Godot graphical version: $GraphicalVersionText" }

$CompileScripts = @(
    "res://scripts/runtime/seamless/sm0/sm0_manual_client_node.gd",
    "res://scripts/runtime/seamless/sm0/sm0_graphical_handoff_lab.gd"
)
if ($NetworkProfile -eq $P31NetworkProfile) {
    $CompileScripts += @(
        "res://scripts/runtime/seamless/sm0/sm0_manual_client_network_delay.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_network_delay.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd"
    )
}
foreach ($ScriptPath in $CompileScripts) {
    Write-Host "[SM0-P1] Compile check: $ScriptPath"
    $CompileExit = Invoke-Sm0P1Godot @("--headless", "--path", $ProjectRoot, "--check-only", "--script", $ScriptPath)
    if ($CompileExit -ne 0) { throw "SM0-P1 compile check failed: $ScriptPath (exit $CompileExit)" }
}
Write-Host "[SM0-P1] Running graphical scene smoke..."
$SmokeExit = Invoke-Sm0P1Godot @("--headless", "--path", $ProjectRoot, "res://scenes/testing/sm0_graphical_handoff_lab.tscn", "--", "--smoke")
if ($SmokeExit -ne 0) { throw "SM0-P1 graphical smoke failed (exit $SmokeExit)" }

function Test-Sm0UdpPortFree([int]$Port) {
    $Udp = $null
    try {
        $Udp = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $Udp.Client.ExclusiveAddressUse = $true
        $Udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    } catch { return $false } finally { if ($null -ne $Udp) { $Udp.Dispose() } }
}
foreach ($Port in @(24580,24581,24680,24681,24780)) {
    if (-not (Test-Sm0UdpPortFree $Port)) { throw "UDP port $Port is already in use." }
}

function Quote-Sm0Arg([string]$Value) { return '"' + $Value + '"' }
function Wait-Sm0Marker([string]$Path, [string]$Marker, [System.Diagnostics.Process]$Process, [int]$Seconds) {
    $Deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $Deadline) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "PID=$($Process.Id) exited before marker $Marker. Log: $Path" }
        if ((Test-Path -LiteralPath $Path) -and (Select-String -LiteralPath $Path -SimpleMatch $Marker -Quiet -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 50
    }
    throw "Timeout waiting for $Marker in $Path"
}

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogDir = Join-Path $LogsRoot $RunId
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ServerALog = Join-Path $LogDir "server-a.log"
$ServerBLog = Join-Path $LogDir "server-b.log"
$ClientLog = Join-Path $LogDir "graphical-client.log"
$StopFile = Join-Path $LogDir "stop.flag"
$ServerA = $null
$ServerB = $null
$Client = $null
$ExitCode = 1

function Start-Sm0Authority([string]$Role, [string]$LogPath, [string[]]$UserArgs) {
    $Arguments = @(
        "--headless", "--path", (Quote-Sm0Arg $ProjectRoot),
        "--log-file", (Quote-Sm0Arg $LogPath),
        "--script", "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd", "--"
    ) + $UserArgs
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $Process = Start-Process -FilePath $GodotConsole -ArgumentList $Arguments -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
    Write-Host "[SM0-P1] $Role PID=$($Process.Id) log=$LogPath"
    return $Process
}

$NetworkArgs = @()
if ($NetworkProfile -eq $P31NetworkProfile) {
    $NetworkArgs = @(
        "--network-profile=$NetworkProfile",
        "--network-latency-ms=$NetworkLatencyMs",
        "--network-jitter-ms=$NetworkJitterMs",
        "--network-seed=$NetworkSeed"
    )
}

try {
    $ServerAArgs = @(
        "--authority-id=authority/sm0/a", "--zone-id=zone/earth/sm0/west",
        "--gameplay-port=24580", "--control-port=24680", "--peer-control-port=24681",
        "--stop-file=$StopFile"
    ) + $NetworkArgs
    $ServerBArgs = @(
        "--authority-id=authority/sm0/b", "--zone-id=zone/earth/sm0/east",
        "--gameplay-port=24581", "--control-port=24681", "--peer-control-port=24680",
        "--stop-file=$StopFile"
    ) + $NetworkArgs
    $ServerA = Start-Sm0Authority "server-a" $ServerALog $ServerAArgs
    $ServerB = Start-Sm0Authority "server-b" $ServerBLog $ServerBArgs

    Wait-Sm0Marker $ServerALog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerA 20
    Wait-Sm0Marker $ServerBLog '"event":"SM0_AUTHORITY_PEER_SYNCED"' $ServerB 20

    $ClientArguments = @(
        "--path", (Quote-Sm0Arg $ProjectRoot),
        "--log-file", (Quote-Sm0Arg $ClientLog),
        "res://scenes/testing/sm0_graphical_handoff_lab.tscn", "--",
        "--server-host=127.0.0.1", "--server-a-port=24580", "--server-b-port=24581", "--client-port=24780"
    )
    if ($NetworkProfile -eq $P31NetworkProfile) {
        $ClientArguments += $NetworkArgs
    }
    $Client = Start-Process -FilePath $GodotGraphical -ArgumentList $ClientArguments -WorkingDirectory $ProjectRoot -PassThru

    $Session = [ordered]@{
        schema = "distributed_world_simulator.sm0_graphical_lab_session.v1"
        git_head = $Head
        project_root = $ProjectRoot
        log_directory = $LogDir
        stop_file = $StopFile
        network_profile = $NetworkProfile
        network_latency_ms = $NetworkLatencyMs
        network_jitter_ms = $NetworkJitterMs
        network_seed = $NetworkSeed
        processes = @(
            [ordered]@{ role = "server-a"; pid = $ServerA.Id },
            [ordered]@{ role = "server-b"; pid = $ServerB.Id },
            [ordered]@{ role = "graphical-client"; pid = $Client.Id }
        )
    }
    $Session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8

    Write-Host ""
    Write-Host "SM0-P1 graphical local lab is running." -ForegroundColor Green
    Write-Host "  A / D : cross WEST <-> EAST authority boundary"
    Write-Host "  W / S : move along the boundary"
    Write-Host "  HUD   : authority, zone, state, epochs, player identity, handoff count"
    if ($NetworkProfile -eq $P31NetworkProfile) {
        Write-Host "  NET   : $NetworkProfile one-way=${NetworkLatencyMs}ms jitter=+/-${NetworkJitterMs}ms seed=$NetworkSeed" -ForegroundColor Yellow
    }
    Write-Host "  Close the Godot window to stop both authority servers."
    Write-Host "  HEAD  : $Head"
    Write-Host "  logs  : $LogDir"
    Write-Host ""

    $Client.WaitForExit()
    New-Item -ItemType File -Force -Path $StopFile | Out-Null
    foreach ($Server in @($ServerA, $ServerB)) {
        $Deadline = (Get-Date).AddSeconds(10)
        while (-not $Server.HasExited -and (Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 50; $Server.Refresh() }
        if (-not $Server.HasExited) { Stop-Process -Id $Server.Id -Force -ErrorAction SilentlyContinue }
    }

    $HandoffCount = 0
    if (Test-Path -LiteralPath $ClientLog) {
        $HandoffCount = @(Select-String -LiteralPath $ClientLog -SimpleMatch '"event":"SM0_CROSSING_COMPLETED"' -ErrorAction SilentlyContinue).Count
    }
    Write-Host "[SM0-P1] Graphical client closed. Observed handoffs: $HandoffCount"
    if ($Client.ExitCode -ne 0) { throw "Graphical client exited with code $($Client.ExitCode). Log: $ClientLog" }
    if ($RequireHandoffs -gt 0 -and $HandoffCount -lt $RequireHandoffs) {
        throw "Expected at least $RequireHandoffs handoffs, observed $HandoffCount."
    }
    $ExitCode = 0
}
catch {
    Write-Error "SM0-P1 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $ExitCode = 1
}
finally {
    foreach ($Process in @($Client, $ServerA, $ServerB)) {
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
    Write-Error "SM0-P1 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $ExitCode
