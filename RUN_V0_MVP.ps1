[CmdletBinding()]
param(
    [ValidateRange(0, 32)]
    [int]$Clients = 2,

    [ValidateRange(1, 65535)]
    [int]$Port = 24580,

    [string]$ServerAddress = "127.0.0.1",
    [string]$World = "earth",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "",

    [ValidateRange(5, 180)]
    [int]$ServerReadyTimeoutSeconds = 60,

    [ValidateRange(0, 10000)]
    [int]$ClientLaunchDelayMs = 1000,

    [ValidateSet("client-a", "server", "none")]
    [string]$RuntimeBridgeOwner = "client-a",

    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowUnstabilized
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Get-Location).Path
}

$LocalAppData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
    $LocalAppData = $env:TEMP
}

$LauncherRoot = Join-Path $LocalAppData "DistributedWorldSimulator\V0MvpLauncher"
$StatePath = Join-Path $LauncherRoot "session.json"
New-Item -ItemType Directory -Force -Path $LauncherRoot | Out-Null

$CallerRuntimeBridgeDisabled = $false
if (Test-Path Env:BREAKPOINT_RUNTIME_DISABLED) {
    $CallerRuntimeBridgeDisabledValue = ([string]$env:BREAKPOINT_RUNTIME_DISABLED).Trim().ToLowerInvariant()
    $CallerRuntimeBridgeDisabled = $CallerRuntimeBridgeDisabledValue -in @("1", "true", "yes", "on")
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -lt 1) {
        return $false
    }
    try {
        Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-PlayerIdentity {
    param([int]$Index)
    if ($Index -lt 26) {
        return ([char](97 + $Index)).ToString()
    }
    return "p$($Index + 1)"
}

function Start-V0ChildProcess {
    param(
        [string]$FilePath,
        [array]$ArgumentList,
        [string]$WorkingDirectory,
        [bool]$EnableRuntimeBridge,
        [switch]$Hidden
    )

    # Windows PowerShell 5.1 Start-Process has no -Environment parameter. Temporarily
    # set the parent process environment only for child creation, then restore it.
    # Every V0 process inherits the same autoload, so exactly one selected process may
    # own the fixed BreakpointRuntimeBridge loopback port (9081 by default).
    $HadDisabledValue = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabledValue = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $ResolvedEnableRuntimeBridge = $EnableRuntimeBridge -and -not $CallerRuntimeBridgeDisabled
        if ($ResolvedEnableRuntimeBridge) {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
        else {
            $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        }

        if ($Hidden) {
            return Start-Process `
                -FilePath $FilePath `
                -ArgumentList $ArgumentList `
                -WorkingDirectory $WorkingDirectory `
                -WindowStyle Hidden `
                -PassThru
        }
        return Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory `
            -PassThru
    }
    finally {
        if ($HadDisabledValue) {
            $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabledValue
        }
        else {
            Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
        }
    }
}

function Get-GitText {
    param([string[]]$Arguments)
    $Value = & git -C $ProjectRoot @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return "unknown"
    }
    return ([string]($Value -join "`n")).Trim()
}

function Test-SourceMarker {
    param(
        [string]$RelativePath,
        [string]$Marker
    )
    $Path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path $Path)) {
        return $false
    }
    return $null -ne (Select-String -Path $Path -SimpleMatch $Marker -Quiet)
}

function Assert-V0StabilizedSource {
    $Checks = @(
        [ordered]@{
            path = "scripts\actors\earth\earth_explorer.gd"
            marker = "_network_surface_view_initialized"
            name = "surface-locked camera"
        },
        [ordered]@{
            path = "scripts\ui\planetary_overlay.gd"
            marker = "_overlay_visible: bool = false"
            name = "hidden debug HUD"
        },
        [ordered]@{
            path = "scripts\network\realtime\realtime_channel_policy.gd"
            marker = "ENET_UNRELIABLE_ORDERED_APPLICATION_SEQUENCED_V1"
            name = "ordered realtime policy"
        },
        [ordered]@{
            path = "scripts\network\transports\v2\enet_multi_peer_transport_port.gd"
            marker = "TRANSFER_MODE_UNRELIABLE_ORDERED"
            name = "ordered ENet transport"
        },
        [ordered]@{
            path = "scripts\runtime\networked_gameplay\m3\m3_graphical_client_runtime_nx6.gd"
            marker = "disconnected_this_poll"
            name = "disconnect timeout guard"
        },
        [ordered]@{
            path = "scripts\app\earth_mvp_app.gd"
            marker = "advance_local_prediction"
            name = "NX4 predicted movement"
        }
    )

    $Missing = @()
    foreach ($Check in $Checks) {
        if (-not (Test-SourceMarker $Check.path $Check.marker)) {
            $Missing += "$($Check.name) [$($Check.path)]"
        }
    }

    $Branch = Get-GitText @("branch", "--show-current")
    $Head = Get-GitText @("rev-parse", "--short=12", "HEAD")
    Write-Host "[V0] Source     : $Branch @ $Head"

    if ($Missing.Count -gt 0) {
        Write-Warning "[V0] Stabilization markers missing:"
        foreach ($Item in $Missing) {
            Write-Warning "  - $Item"
        }
        if (-not $AllowUnstabilized) {
            throw "Refusing to launch a stale/partial V0 checkout. Synchronize the V0-S0 source set first, or use -AllowUnstabilized only for deliberate legacy diagnostics."
        }
        Write-Warning "[V0] -AllowUnstabilized was supplied; continuing with a non-checkpoint source tree."
    }
    else {
        Write-Host "[V0] Source gate: V0-S0 markers present." -ForegroundColor Green
    }

    return [ordered]@{
        branch = $Branch
        head = $Head
        stabilized = ($Missing.Count -eq 0)
    }
}

function Save-SessionState {
    param(
        $ServerProcess,
        [array]$ClientRecords,
        [string]$LogDirectory,
        [string]$StartedUtc,
        $SourceIdentity
    )

    $ServerProcessId = 0
    if ($null -ne $ServerProcess) {
        $ServerProcessId = $ServerProcess.Id
    }

    $State = [ordered]@{
        schema = "distributed_world_simulator.v0_mvp_launcher.v2"
        started_utc = $StartedUtc
        project_root = $ProjectRoot
        source = $SourceIdentity
        server_address = $ServerAddress
        port = $Port
        world = $World
        godot_server_exe = $GodotExe
        godot_client_exe = $GodotGuiExe
        runtime_bridge_owner = $RuntimeBridgeOwner
        log_directory = $LogDirectory
        server = [ordered]@{
            pid = $ServerProcessId
            log = Join-Path $LogDirectory "server.log"
        }
        clients = @($ClientRecords)
    }

    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding UTF8
}

function Stop-ManagedSession {
    if (-not (Test-Path $StatePath)) {
        Write-Host "[V0] No managed session is recorded."
        return
    }

    try {
        $State = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "[V0] Session state is unreadable; removing stale state file."
        Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
        return
    }

    foreach ($Client in @($State.clients)) {
        $ClientPid = [int]$Client.pid
        if (Test-ProcessAlive $ClientPid) {
            Write-Host "[V0] Stopping client $($Client.identity) (PID $ClientPid)..."
            Stop-Process -Id $ClientPid -Force -ErrorAction SilentlyContinue
        }
    }

    $ServerPid = [int]$State.server.pid
    if (Test-ProcessAlive $ServerPid) {
        Write-Host "[V0] Stopping server (PID $ServerPid)..."
        Stop-Process -Id $ServerPid -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
    Write-Host "[V0] Managed session stopped."
}

if ($Stop) {
    Stop-ManagedSession
    exit 0
}

if (-not (Test-Path $GodotExe)) {
    throw "Godot console executable not found: $GodotExe"
}

if ([string]::IsNullOrWhiteSpace($GodotGuiExe)) {
    $CandidateGuiExe = $GodotExe -replace '\.console\.exe$', '.exe'
    if (Test-Path $CandidateGuiExe) {
        $GodotGuiExe = $CandidateGuiExe
    }
    else {
        $GodotGuiExe = $GodotExe
    }
}

if (-not (Test-Path $GodotGuiExe)) {
    throw "Godot graphical executable not found: $GodotGuiExe"
}

if (Test-Path $StatePath) {
    $Existing = $null
    try {
        $Existing = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
    }
    catch {
        Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $Existing) {
        $RunningPids = @()
        $ExistingServerPid = [int]$Existing.server.pid
        if (Test-ProcessAlive $ExistingServerPid) {
            $RunningPids += $ExistingServerPid
        }
        foreach ($ExistingClient in @($Existing.clients)) {
            $ExistingClientPid = [int]$ExistingClient.pid
            if (Test-ProcessAlive $ExistingClientPid) {
                $RunningPids += $ExistingClientPid
            }
        }

        if ($RunningPids.Count -gt 0) {
            if ($Restart) {
                Stop-ManagedSession
            }
            else {
                $RunningText = $RunningPids -join ", "
                throw "A V0 session is already running (PIDs: $RunningText). Use .\RUN_V0_MVP.ps1 -Stop or add -Restart."
            }
        }
        else {
            Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
        }
    }
}

$SourceIdentity = Assert-V0StabilizedSource
$SessionId = Get-Date -Format "yyyyMMdd-HHmmss"
$StartedUtc = (Get-Date).ToUniversalTime().ToString("o")
$LogDirectory = Join-Path $LauncherRoot "logs\$SessionId"
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

$ServerLog = Join-Path $LogDirectory "server.log"
$ServerProcess = $null
$ClientRecords = @()
$SpawnedProcesses = @()

try {
    $ServerArgs = @(
        "--headless",
        "--path", ('"' + $ProjectRoot + '"'),
        "--log-file", ('"' + $ServerLog + '"'),
        "--",
        "--network-mvp",
        "--role=dedicated-server",
        "--world=$World",
        "--server-address=$ServerAddress",
        "--server-port=$Port",
        "--network-debug",
        "--network-debug-stay-open"
    )

    $ServerRuntimeBridgeEnabled = ($RuntimeBridgeOwner -eq "server")
    Write-Host "[V0] Starting dedicated server on $ServerAddress`:$Port..."
    $ServerProcess = Start-V0ChildProcess `
        -FilePath $GodotExe `
        -ArgumentList $ServerArgs `
        -WorkingDirectory $ProjectRoot `
        -EnableRuntimeBridge $ServerRuntimeBridgeEnabled `
        -Hidden
    $SpawnedProcesses += $ServerProcess
    Save-SessionState $ServerProcess $ClientRecords $LogDirectory $StartedUtc $SourceIdentity

    $Deadline = (Get-Date).AddSeconds($ServerReadyTimeoutSeconds)
    $ServerReady = $false
    while ((Get-Date) -lt $Deadline) {
        if ($ServerProcess.HasExited) {
            throw "Dedicated server exited early with code $($ServerProcess.ExitCode). Log: $ServerLog"
        }

        if (Test-Path $ServerLog) {
            $ReadyMatch = Get-Content -Path $ServerLog -Tail 250 -ErrorAction SilentlyContinue |
                Select-String -SimpleMatch '"event":"SERVER_READY"' |
                Select-Object -First 1
            if ($null -ne $ReadyMatch) {
                $ServerReady = $true
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }

    if (-not $ServerReady) {
        throw "Server did not report SERVER_READY within $ServerReadyTimeoutSeconds seconds. Log: $ServerLog"
    }

    Write-Host "[V0] Server ready (PID $($ServerProcess.Id))."

    if ($Clients -gt 0) {
        for ($Index = 0; $Index -lt $Clients; $Index++) {
            $Identity = Get-PlayerIdentity $Index
            $ClientLog = Join-Path $LogDirectory "client-$Identity.log"
            $ClientArgs = @(
                "--path", ('"' + $ProjectRoot + '"'),
                "--log-file", ('"' + $ClientLog + '"'),
                "--",
                "--network-mvp",
                "--role=game-client",
                "--world=$World",
                "--server-address=$ServerAddress",
                "--server-port=$Port",
                "--player-identity=$Identity",
                "--network-debug",
                "--network-debug-stay-open"
            )

            $ClientRuntimeBridgeEnabled = ($RuntimeBridgeOwner -eq "client-a" -and $Identity -eq "a")
            Write-Host "[V0] Starting client $Identity..."
            $ClientProcess = Start-V0ChildProcess `
                -FilePath $GodotGuiExe `
                -ArgumentList $ClientArgs `
                -WorkingDirectory $ProjectRoot `
                -EnableRuntimeBridge $ClientRuntimeBridgeEnabled `
                -Hidden:($GodotGuiExe -eq $GodotExe)

            $SpawnedProcesses += $ClientProcess
            $ClientRecord = [ordered]@{
                identity = $Identity
                pid = $ClientProcess.Id
                log = $ClientLog
                runtime_bridge = $ClientRuntimeBridgeEnabled -and -not $CallerRuntimeBridgeDisabled
            }
            $ClientRecords += $ClientRecord
            Save-SessionState $ServerProcess $ClientRecords $LogDirectory $StartedUtc $SourceIdentity

            if ($ClientLaunchDelayMs -gt 0 -and $Index -lt ($Clients - 1)) {
                Start-Sleep -Milliseconds $ClientLaunchDelayMs
            }
        }
    }
}
catch {
    Write-Error $_
    foreach ($Process in @($SpawnedProcesses)) {
        if ($null -ne $Process -and -not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host ""
Write-Host "[V0] Session started successfully." -ForegroundColor Green
Write-Host "[V0] Server PID : $($ServerProcess.Id)"
if ($CallerRuntimeBridgeDisabled) {
    Write-Host "[V0] Runtime MCP: disabled by BREAKPOINT_RUNTIME_DISABLED" -ForegroundColor DarkGray
}
else {
    Write-Host "[V0] Runtime MCP: $RuntimeBridgeOwner" -ForegroundColor DarkGray
}
if ($ClientRecords.Count -gt 0) {
    Write-Host "[V0] Clients    : $($ClientRecords.Count)"
    foreach ($ClientRecord in $ClientRecords) {
        $BridgeSuffix = ""
        if ([bool]$ClientRecord.runtime_bridge) {
            $BridgeSuffix = " +runtime-mcp"
        }
        Write-Host "       $($ClientRecord.identity) -> PID $($ClientRecord.pid)$BridgeSuffix"
    }
}
else {
    Write-Host "[V0] Clients    : 0"
}
Write-Host "[V0] Logs       : $LogDirectory"
Write-Host ""
Write-Host "Stop all:"
Write-Host "  .\RUN_V0_MVP.ps1 -Stop"
Write-Host ""
Write-Host "Restart with another client count:"
Write-Host "  .\RUN_V0_MVP.ps1 -Clients 4 -Restart"
Write-Host ""
Write-Host "Follow server log:"
Write-Host "  Get-Content `"$ServerLog`" -Wait"