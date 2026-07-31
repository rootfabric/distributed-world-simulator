param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [ValidatePattern('^[a-z0-9_-]+$')][string]$PlayerId = "a",
    [string]$SessionId = "manual",
    [string]$ServerAddress = "127.0.0.1",
    [ValidateRange(1, 65535)][int]$Port = 24580,
    [ValidateRange(1, 120)][int]$ServerReadyTimeoutSeconds = 40
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path
$RunRoot = Join-Path $ProjectRoot "artifacts/runtime/m7-network-debug/$SessionId"
$ServerStatePath = Join-Path $RunRoot "server/server-state.json"
$ServerProcessPath = Join-Path $RunRoot "server/process.json"
$RoleName = "client-$PlayerId"
$RoleRoot = Join-Path $RunRoot $RoleName
$ProfileRoot = Join-Path $RoleRoot "profile"
$LogPath = Join-Path $RoleRoot "godot.log"
$ProcessPath = Join-Path $RoleRoot "process.json"
New-Item -ItemType Directory -Force -Path $RoleRoot,$ProfileRoot | Out-Null
Remove-Item $LogPath,$ProcessPath -Force -ErrorAction SilentlyContinue

$Deadline = [DateTime]::UtcNow.AddSeconds($ServerReadyTimeoutSeconds)
$ServerState = $null
while ([DateTime]::UtcNow -lt $Deadline) {
    if (Test-Path $ServerStatePath) {
        try { $ServerState = Get-Content $ServerStatePath -Raw | ConvertFrom-Json } catch { $ServerState = $null }
        if ($null -ne $ServerState -and $ServerState.state -eq "READY") { break }
        if ($null -ne $ServerState -and $ServerState.state -eq "FAILED") {
            throw "M7 server reported FAILED. See $(Join-Path $RunRoot 'server/godot.log')"
        }
    }
    Start-Sleep -Milliseconds 100
}
if ($null -eq $ServerState -or $ServerState.state -ne "READY") {
    throw "M7 server is not READY at $ServerAddress`:$Port. Start START_M7_NETWORK_SERVER.ps1 first."
}

if (-not (Test-Path $ServerProcessPath)) {
    throw "M7 server process descriptor is missing: $ServerProcessPath"
}
try {
    $ServerProcess = Get-Content $ServerProcessPath -Raw | ConvertFrom-Json
}
catch {
    throw "M7 server process descriptor is invalid: $ServerProcessPath"
}
$ServerPid = [int]$ServerProcess.pid
$LiveServer = Get-Process -Id $ServerPid -ErrorAction SilentlyContinue
if ($null -eq $LiveServer) {
    throw "M7 server state is stale: process $ServerPid is not running. Restart START_M7_NETWORK_SERVER.ps1."
}
if ($ServerProcess.session_id -ne $SessionId) {
    throw "M7 server session mismatch: expected '$SessionId', got '$($ServerProcess.session_id)'."
}
if ($ServerProcess.endpoint -ne "$ServerAddress`:$Port") {
    throw "M7 server endpoint mismatch: expected $ServerAddress`:$Port, got $($ServerProcess.endpoint)."
}

function Start-IsolatedProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Profile)
    $Data = Join-Path $Profile "data"
    $Config = Join-Path $Profile "config"
    $Cache = Join-Path $Profile "cache"
    New-Item -ItemType Directory -Force -Path $Profile,$Data,$Config,$Cache | Out-Null
    $Names = @("HOME","USERPROFILE","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","BREAKPOINT_RUNTIME_DISABLED","GODOT_SILENCE_ROOT_WARNING")
    $Saved = @{}
    foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
    try {
        $env:HOME = $Profile
        $env:USERPROFILE = $Profile
        $env:APPDATA = $Data
        $env:LOCALAPPDATA = $Data
        $env:XDG_DATA_HOME = $Data
        $env:XDG_CONFIG_HOME = $Config
        $env:XDG_CACHE_HOME = $Cache
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        $env:GODOT_SILENCE_ROOT_WARNING = "1"
        return Start-Process -FilePath $Executable -ArgumentList $Arguments -NoNewWindow -PassThru
    }
    finally {
        foreach ($Name in $Names) {
            $Value = $Saved[$Name]
            if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($Name, $Value, "Process") }
        }
    }
}

$Arguments = @(
    "--path",$ProjectRoot,"--rendering-method","gl_compatibility","--log-file",$LogPath,"--",
    "--role=game-client","--network-playground","--network-debug","--network-debug-stay-open","--world=playground",
    "--node-id=m7-debug-client-$PlayerId","--instance-id=m7-debug-$SessionId-$PlayerId",
    "--player-identity=$PlayerId","--server-address=$ServerAddress","--server-port=$Port",
    "--print-runtime-descriptor"
)

Write-Host "M7 graphical client $PlayerId" -ForegroundColor Cyan
Write-Host "Session:  $SessionId"
Write-Host "Server:   $ServerAddress`:$Port"
Write-Host "Log:      $LogPath"
Write-Host "The window remains open after network failure; the error is printed here and in the log." -ForegroundColor Yellow

$Process = Start-IsolatedProcess -Executable $Godot -Arguments $Arguments -Profile $ProfileRoot
$Descriptor = [ordered]@{
    schema = "planet_simulator.m7_network_debug_process.v1"
    session_id = $SessionId
    role = $RoleName
    player_id = $PlayerId
    pid = $Process.Id
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    log_path = $LogPath
    endpoint = "$ServerAddress`:$Port"
    godot_path = $Godot
    server_pid = $ServerPid
}
$Descriptor | ConvertTo-Json -Depth 5 | Set-Content -Path $ProcessPath -Encoding UTF8
try {
    $Process.WaitForExit()
    $Descriptor.exit_code = $Process.ExitCode
    $Descriptor.exited_at_utc = [DateTime]::UtcNow.ToString("o")
    $Descriptor | ConvertTo-Json -Depth 5 | Set-Content -Path $ProcessPath -Encoding UTF8
    Write-Host "Client $PlayerId exited with code $($Process.ExitCode). Log: $LogPath" -ForegroundColor Yellow
    exit $Process.ExitCode
}
finally {
    if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
}
