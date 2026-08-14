param(
    [string]$GodotPath = "",
    [string]$ServerAddress = "127.0.0.1",
    [ValidateRange(1, 65535)][int]$Port = 24580,
    [ValidateRange(640, 3840)][int]$ClientWidth = 900,
    [ValidateRange(360, 2160)][int]$ClientHeight = 600,
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ActiveSessionPath = Join-Path $Root "artifacts/runtime/v0-local-two-player-active.json"

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Godot 4.7.1 double-precision executable was not found. Pass -GodotPath or set GODOT_BIN."
}

function Resolve-GraphicalGodotExecutable {
    param([string]$ConsoleExecutable)
    if ($ConsoleExecutable.EndsWith(".console.exe", [StringComparison]::OrdinalIgnoreCase)) {
        $Graphical = $ConsoleExecutable.Substring(0, $ConsoleExecutable.Length - ".console.exe".Length) + ".exe"
        if (Test-Path $Graphical) { return (Resolve-Path $Graphical).Path }
    }
    return $ConsoleExecutable
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Start-IsolatedGodot {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$ProfileRoot,
        [switch]$Hidden
    )
    $Data = Join-Path $ProfileRoot "data"
    $Config = Join-Path $ProfileRoot "config"
    $Cache = Join-Path $ProfileRoot "cache"
    New-Item -ItemType Directory -Force -Path $ProfileRoot,$Data,$Config,$Cache | Out-Null

    $Names = @(
        "HOME","USERPROFILE","APPDATA","LOCALAPPDATA",
        "XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME",
        "BREAKPOINT_RUNTIME_DISABLED","GODOT_SILENCE_ROOT_WARNING"
    )
    $Saved = @{}
    foreach ($Name in $Names) {
        $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    }
    try {
        $env:HOME = $ProfileRoot
        $env:USERPROFILE = $ProfileRoot
        $env:APPDATA = $Data
        $env:LOCALAPPDATA = $Data
        $env:XDG_DATA_HOME = $Data
        $env:XDG_CONFIG_HOME = $Config
        $env:XDG_CACHE_HOME = $Cache
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $env:GODOT_SILENCE_ROOT_WARNING = "1"
        $Start = @{
            FilePath = $Executable
            ArgumentList = $Arguments
            PassThru = $true
        }
        if ($Hidden) { $Start.WindowStyle = "Hidden" }
        return Start-Process @Start
    }
    finally {
        foreach ($Name in $Names) {
            $Value = $Saved[$Name]
            if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($Name, $Value, "Process") }
        }
    }
}

function Invoke-ImportPreflight {
    param(
        [string]$Executable,
        [string]$ProfileRoot,
        [string]$LogFile
    )
    $Process = Start-IsolatedGodot -Executable $Executable -Arguments @(
        "--headless","--editor","--path",$Root,"--log-file",$LogFile,"--quit"
    ) -ProfileRoot $ProfileRoot -Hidden
    $Process.WaitForExit()
    if ($Process.ExitCode -ne 0) {
        throw "Godot import preflight failed with exit code $($Process.ExitCode). See $LogFile"
    }
}

function Stop-SessionProcesses {
    param([int]$ServerPid, [int[]]$ClientPids)
    foreach ($PidToStop in @($ClientPids) + @($ServerPid)) {
        if (Test-ProcessAlive $PidToStop) {
            Stop-Process -Id $PidToStop -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SpawnDistance {
    param($ServerState)
    $Players = @($ServerState.snapshot.players)
    $A = $Players | Where-Object { $_.logical_player_id -eq "a" } | Select-Object -First 1
    $B = $Players | Where-Object { $_.logical_player_id -eq "b" } | Select-Object -First 1
    if ($null -eq $A -or $null -eq $B) { return -1.0 }
    $Dx = [double]$A.position.x - [double]$B.position.x
    $Dy = [double]$A.position.y - [double]$B.position.y
    $Dz = [double]$A.position.z - [double]$B.position.z
    return [Math]::Sqrt($Dx * $Dx + $Dy * $Dy + $Dz * $Dz)
}

if (Test-Path $ActiveSessionPath) {
    $Existing = Get-Content $ActiveSessionPath -Raw | ConvertFrom-Json
    $Running = @($Existing.server_pid) + @($Existing.client_pids) | Where-Object {
        Test-ProcessAlive ([int]$_)
    }
    if ($Running.Count -gt 0) {
        throw "A V0 local two-player session is already running. Use .\STOP_V0_LOCAL_TWO_PLAYER.ps1 first."
    }
    Remove-Item $ActiveSessionPath -Force
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$GraphicalGodot = Resolve-GraphicalGodotExecutable -ConsoleExecutable $Godot
$Version = (& $Godot --version 2>&1 | Out-String).Trim()
if ($Version -notmatch "double") {
    throw "V0 local two-player launch requires the double-precision Godot build. Resolved: $Version"
}

$RunId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$RunRoot = Join-Path $Root "artifacts/runtime/v0-local-two-player/$RunId"
$Profiles = Join-Path $RunRoot "profiles"
New-Item -ItemType Directory -Force -Path $RunRoot,$Profiles | Out-Null
$NetworkSessionToken = "session-id/v0-local-$($RunId.ToLowerInvariant())"

if (-not $SkipImport) {
    Write-Host "[1/5] Importing/checking project with $Version ..." -ForegroundColor Cyan
    Invoke-ImportPreflight `
        -Executable $Godot `
        -ProfileRoot (Join-Path $Profiles "preflight") `
        -LogFile (Join-Path $RunRoot "preflight.log")
}

Write-Host "[2/5] Starting dedicated Earth server ..." -ForegroundColor Cyan
$ServerResult = Join-Path $RunRoot "server.json"
$ServerLog = Join-Path $RunRoot "server.log"
$ServerArgs = @(
    "--headless","--path",$Root,"--log-file",$ServerLog,"--",
    "--role=dedicated-server","--network-mvp","--network-debug","--world=earth",
    "--node-id=v0-local-server","--instance-id=v0-local-server",
    "--server-address=$ServerAddress","--server-port=$Port",
    "--network-session-token=$NetworkSessionToken","--network-profile=LOCAL",
    "--m3-result-file=$ServerResult","--print-runtime-descriptor"
)
$Server = Start-IsolatedGodot `
    -Executable $Godot `
    -Arguments $ServerArgs `
    -ProfileRoot (Join-Path $Profiles "server") `
    -Hidden

$Deadline = [DateTime]::UtcNow.AddSeconds(45)
$ServerState = $null
while ([DateTime]::UtcNow -lt $Deadline) {
    if (-not (Test-ProcessAlive $Server.Id)) { break }
    if (Test-Path $ServerResult) {
        try { $ServerState = Get-Content $ServerResult -Raw | ConvertFrom-Json }
        catch { $ServerState = $null }
        if ($null -ne $ServerState -and $ServerState.state -in @("READY","FAILED")) { break }
    }
    Start-Sleep -Milliseconds 100
}
if ($null -eq $ServerState -or $ServerState.state -ne "READY") {
    if (Test-ProcessAlive $Server.Id) { Stop-Process -Id $Server.Id -Force }
    throw "V0 dedicated server did not become READY. See $ServerLog"
}

Write-Host "[3/5] Starting Client A and Client B ..." -ForegroundColor Cyan
$ClientPids = @()
$ClientDefinitions = @(
    @{ id = "a"; x = 20;  y = 80 },
    @{ id = "b"; x = 940; y = 80 }
)
foreach ($ClientDefinition in $ClientDefinitions) {
    $Id = [string]$ClientDefinition.id
    $ClientLog = Join-Path $RunRoot "client-$Id.log"
    $WindowPosition = "$($ClientDefinition.x),$($ClientDefinition.y)"
    $ClientArgs = @(
        "--path",$Root,
        "--rendering-method","gl_compatibility",
        "--resolution","$($ClientWidth)x$($ClientHeight)",
        "--position",$WindowPosition,
        "--log-file",$ClientLog,
        "--",
        "--role=game-client","--network-mvp","--network-debug","--network-debug-stay-open","--world=earth",
        "--node-id=v0-local-client-$Id","--instance-id=v0-local-client-$Id",
        "--player-identity=$Id","--server-address=$ServerAddress","--server-port=$Port",
        "--network-session-token=$NetworkSessionToken","--network-profile=LOCAL",
        "--print-runtime-descriptor"
    )
    $Client = Start-IsolatedGodot `
        -Executable $GraphicalGodot `
        -Arguments $ClientArgs `
        -ProfileRoot (Join-Path $Profiles "client-$Id")
    $ClientPids += $Client.Id
    Start-Sleep -Milliseconds 500
}

Write-Host "[4/5] Waiting until the server confirms both players joined ..." -ForegroundColor Cyan
$JoinDeadline = [DateTime]::UtcNow.AddSeconds(45)
$TwoPlayerState = $null
while ([DateTime]::UtcNow -lt $JoinDeadline) {
    if (-not (Test-ProcessAlive $Server.Id)) { break }
    $DeadClient = $ClientPids | Where-Object { -not (Test-ProcessAlive ([int]$_)) } | Select-Object -First 1
    if ($null -ne $DeadClient) { break }
    if (Test-Path $ServerResult) {
        try { $CandidateState = Get-Content $ServerResult -Raw | ConvertFrom-Json }
        catch { $CandidateState = $null }
        if ($null -ne $CandidateState -and $CandidateState.state -eq "FAILED") { break }
        if ($null -ne $CandidateState -and [int]$CandidateState.connected_peer_count -eq 2) {
            $JoinedPlayers = @($CandidateState.peer_to_player.PSObject.Properties | ForEach-Object { [string]$_.Value })
            if ($JoinedPlayers -contains "a" -and $JoinedPlayers -contains "b") {
                $TwoPlayerState = $CandidateState
                break
            }
        }
    }
    Start-Sleep -Milliseconds 100
}
if ($null -eq $TwoPlayerState) {
    Stop-SessionProcesses -ServerPid $Server.Id -ClientPids $ClientPids
    throw "Server did not confirm both Client A and Client B within 45 seconds. See $ServerLog and client logs in $RunRoot"
}

$SpawnDistance = Get-SpawnDistance -ServerState $TwoPlayerState
if ($SpawnDistance -lt 0.0 -or $SpawnDistance -gt 12.0) {
    Stop-SessionProcesses -ServerPid $Server.Id -ClientPids $ClientPids
    throw "Two players joined, but spawn distance is not suitable for local inspection: $SpawnDistance m. See $ServerResult"
}

$Session = [ordered]@{
    schema = "planet_simulator.v0_local_two_player_session.v1"
    milestone = "TWO_PLAYER_PLAYABLE_BUILD"
    run_id = $RunId
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    project_root = $Root
    godot = $Godot
    godot_version = $Version
    server_address = $ServerAddress
    server_port = $Port
    server_pid = $Server.Id
    client_pids = $ClientPids
    client_ids = @("a","b")
    connected_peer_count = [int]$TwoPlayerState.connected_peer_count
    spawn_distance_m = $SpawnDistance
    world_id = "earth"
    network_mode = "SERVER_PREDICTED"
    network_session_token = $NetworkSessionToken
    run_root = $RunRoot
}
$Session | ConvertTo-Json -Depth 6 | Set-Content -Path $ActiveSessionPath -Encoding UTF8
$Session | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $RunRoot "session.json") -Encoding UTF8

Write-Host "[5/5] TWO_PLAYER_PLAYABLE_BUILD is running." -ForegroundColor Green
Write-Host ""
Write-Host "Server confirmed: connected_peer_count=2; players=a,b"
Write-Host ("Authoritative spawn distance: {0:N2} m" -f $SpawnDistance)
Write-Host "Client A: left window, player 'a'"
Write-Host "Client B: right window, player 'b'"
Write-Host "World: Earth / same server $ServerAddress`:$Port"
Write-Host "Server PID: $($Server.Id); client PIDs: $($ClientPids -join ', ')"
Write-Host "Logs: $RunRoot"
Write-Host ""
Write-Host "Manual check:" -ForegroundColor Yellow
Write-Host "  1. Click Client A, move with WASD, then look at Client B."
Write-Host "  2. Client B must show A in the new position."
Write-Host "  3. Move B with WASD, then look at Client A."
Write-Host "  4. Client A must show B in the new position."
Write-Host "  5. A and B must remain on the same Earth surface patch."
Write-Host ""
Write-Host "Controls: click viewport to capture mouse; WASD move; Shift run; Space jump; Tab releases/captures mouse when inventory is unavailable."
Write-Host "Stop everything: .\STOP_V0_LOCAL_TWO_PLAYER.ps1"
