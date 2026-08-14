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

    [switch]$Stop,
    [switch]$Restart
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

function Save-SessionState {
    param(
        $ServerProcess,
        [array]$ClientRecords,
        [string]$LogDirectory,
        [string]$StartedUtc
    )

    $State = [ordered]@{
        schema = "distributed_world_simulator.v0_mvp_launcher.v1"
        started_utc = $StartedUtc
        project_root = $ProjectRoot
        server_address = $ServerAddress
        port = $Port
        world = $World
        godot_server_exe = $GodotExe
        godot_client_exe = $GodotGuiExe
        log_directory = $LogDirectory
        server = [ordered]@{
            pid = if ($null -ne $ServerProcess) { $ServerProcess.Id } else { 0 }
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
                throw (
                    "A V0 session is already running (PIDs: {0}). " +
                    "Use .\RUN_V0_MVP.ps1 -Stop or add -Restart."
                ) -f ($RunningPids -join ", ")
            }
        }
        else {
            Remove-Item -Path $StatePath -Force -ErrorAction SilentlyContinue
        }
    }
}

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

    Write-Host "[V0] Starting dedicated server on $ServerAddress`:$Port..."
    $ServerProcess = Start-Process `
        -FilePath $GodotExe `
        -ArgumentList $ServerArgs `
        -WorkingDirectory $ProjectRoot `
        -WindowStyle Hidden `
        -PassThru
    $SpawnedProcesses += $ServerProcess
    Save-SessionState $ServerProcess $ClientRecords $LogDirectory $StartedUtc

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

            Write-Host "[V0] Starting client $Identity..."
            if ($GodotGuiExe -eq $GodotExe) {
                $ClientProcess = Start-Process `
                    -FilePath $GodotGuiExe `
                    -ArgumentList $ClientArgs `
                    -WorkingDirectory $ProjectRoot `
                    -WindowStyle Hidden `
                    -PassThru
            }
            else {
                $ClientProcess = Start-Process `
                    -FilePath $GodotGuiExe `
                    -ArgumentList $ClientArgs `
                    -WorkingDirectory $ProjectRoot `
                    -PassThru
            }

            $SpawnedProcesses += $ClientProcess
            $ClientRecord = [ordered]@{
                identity = $Identity
                pid = $ClientProcess.Id
                log = $ClientLog
            }
            $ClientRecords += $ClientRecord
            Save-SessionState $ServerProcess $ClientRecords $LogDirectory $StartedUtc

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
if ($ClientRecords.Count -gt 0) {
    Write-Host "[V0] Clients    : $($ClientRecords.Count)"
    foreach ($ClientRecord in $ClientRecords) {
        Write-Host "       $($ClientRecord.identity) -> PID $($ClientRecord.pid)"
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
