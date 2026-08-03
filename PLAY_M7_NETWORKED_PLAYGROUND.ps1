param(
    [string]$GodotPath = "",
    [string]$ServerAddress = "127.0.0.1",
    [ValidateRange(1, 65535)][int]$Port = 24580,
    [ValidateRange(1, 8)][int]$ClientCount = 2,
    [ValidateSet("LOCAL","GOOD_BROADBAND","AVERAGE_BROADBAND","MOBILE","BAD_MOBILE","EXTREME","LAG_SPIKE","ASYMMETRIC")][string]$ServerNetworkProfile = "LOCAL",
    [ValidateSet("LOCAL","GOOD_BROADBAND","AVERAGE_BROADBAND","MOBILE","BAD_MOBILE","EXTREME","LAG_SPIKE","ASYMMETRIC")][string]$ClientNetworkProfile = "LOCAL",
    [string]$NetworkPresetsFile = "res://config/network/network-condition-presets.v1.json",
    [string]$PersistenceRoot = "",
    [switch]$ResetPersistence
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ActiveSessionPath = Join-Path $Root "artifacts/runtime/m7-network-playground-active.json"

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
    throw "Godot 4.7.1 double-precision console executable was not found. Pass -GodotPath."
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
    foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
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
        $Start = @{ FilePath = $Executable; ArgumentList = $Arguments; PassThru = $true }
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

if (Test-Path $ActiveSessionPath) {
    $Existing = Get-Content $ActiveSessionPath -Raw | ConvertFrom-Json
    $Running = @($Existing.server_pid) + @($Existing.client_pids) | Where-Object { Test-ProcessAlive ([int]$_) }
    if ($Running.Count -gt 0) {
        throw "M7 playground is already running. Use .\STOP_M7_NETWORKED_PLAYGROUND.ps1 first."
    }
    Remove-Item $ActiveSessionPath -Force
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$RunId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$NetworkSessionToken = if ([string]::IsNullOrWhiteSpace($env:NX0_NETWORK_SESSION_TOKEN)) { "session-id/m7-$($RunId.ToLowerInvariant())" } else { $env:NX0_NETWORK_SESSION_TOKEN.ToLowerInvariant() }
$RunRoot = Join-Path $Root "artifacts/runtime/m7-network-playground/$RunId"
$Profiles = Join-Path $RunRoot "profiles"
New-Item -ItemType Directory -Force -Path $RunRoot,$Profiles | Out-Null
if ([string]::IsNullOrWhiteSpace($PersistenceRoot)) {
    $PersistenceRoot = Join-Path $Root "artifacts/runtime/m7-network-playground-persistence"
}
if ($ResetPersistence -and (Test-Path $PersistenceRoot)) { Remove-Item $PersistenceRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $PersistenceRoot | Out-Null

$ServerResult = Join-Path $RunRoot "server.json"
$ServerLog = Join-Path $RunRoot "server.log"
$ServerArgs = @(
    "--headless","--path",$Root,"--log-file",$ServerLog,"--",
    "--role=dedicated-server","--network-playground","--network-debug","--world=playground",
    "--network-session-token=$NetworkSessionToken",
    "--node-id=m7-playground-server","--instance-id=m7-playground",
    "--server-address=$ServerAddress","--server-port=$Port",
    "--network-profile=$ServerNetworkProfile","--network-presets-file=$NetworkPresetsFile",
    "--m7-result-file=$ServerResult","--m6-persistence-root=$PersistenceRoot",
    "--print-runtime-descriptor"
)
$Server = Start-IsolatedGodot -Executable $Godot -Arguments $ServerArgs -ProfileRoot (Join-Path $Profiles "server") -Hidden

$Deadline = [DateTime]::UtcNow.AddSeconds(40)
$ServerState = $null
while ([DateTime]::UtcNow -lt $Deadline) {
    if (-not (Test-ProcessAlive $Server.Id)) { break }
    if (Test-Path $ServerResult) {
        try { $ServerState = Get-Content $ServerResult -Raw | ConvertFrom-Json } catch { $ServerState = $null }
        if ($null -ne $ServerState -and $ServerState.state -in @("READY","FAILED")) { break }
    }
    Start-Sleep -Milliseconds 100
}
if ($null -eq $ServerState -or $ServerState.state -ne "READY") {
    if (Test-ProcessAlive $Server.Id) { Stop-Process -Id $Server.Id -Force }
    throw "M7 dedicated server did not become READY. See $ServerLog"
}

$ClientIds = @("a","b","c","d","e","f","g","h")
$ClientPids = @()
for ($Index = 0; $Index -lt $ClientCount; $Index++) {
    $Id = $ClientIds[$Index]
    $ClientLog = Join-Path $RunRoot "client-$Id.log"
    $ClientArgs = @(
        "--path",$Root,"--rendering-method","gl_compatibility","--log-file",$ClientLog,"--",
        "--role=game-client","--network-playground","--network-debug","--network-debug-stay-open","--world=playground",
        "--network-session-token=$NetworkSessionToken",
        "--node-id=m7-client-$Id","--instance-id=m7-client-$Id",
        "--player-identity=$Id","--server-address=$ServerAddress","--server-port=$Port",
        "--network-profile=$ClientNetworkProfile","--network-presets-file=$NetworkPresetsFile",
        "--print-runtime-descriptor"
    )
    $Client = Start-IsolatedGodot -Executable $Godot -Arguments $ClientArgs -ProfileRoot (Join-Path $Profiles "client-$Id")
    $ClientPids += $Client.Id
    Start-Sleep -Milliseconds 350
}

$Session = [ordered]@{
    schema = "planet_simulator.m7_playable_networked_playground_session.v1"
    checkpoint = "v16.11.0-network-nx1-deterministic-condition-simulator"
    run_id = $RunId
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    project_root = $Root
    godot = $Godot
    server_address = $ServerAddress
    server_port = $Port
    server_pid = $Server.Id
    client_pids = $ClientPids
    client_count = $ClientCount
    run_root = $RunRoot
    persistence_root = $PersistenceRoot
    network_session_token = $NetworkSessionToken
    server_network_profile = $ServerNetworkProfile
    client_network_profile = $ClientNetworkProfile
    network_presets_file = $NetworkPresetsFile
}
$Session | ConvertTo-Json -Depth 6 | Set-Content -Path $ActiveSessionPath -Encoding UTF8
$Session | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $RunRoot "session.json") -Encoding UTF8

Write-Host ""
Write-Host "M7 network playground started." -ForegroundColor Green
Write-Host "Server: $ServerAddress`:$Port (PID $($Server.Id))"
Write-Host "Clients: $($ClientPids -join ', ')"
Write-Host "Logs: $RunRoot"
Write-Host "Network profiles: server=$ServerNetworkProfile client=$ClientNetworkProfile"
if ($ServerNetworkProfile -ne "LOCAL" -and $ClientNetworkProfile -ne "LOCAL") {
    Write-Host "Endpoint profiles are additive; applying the same preset at both ends roughly doubles path impairment." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Controls: click viewport to capture mouse; WASD move; Shift run; Space jump; Tab inventory; E interact/pick up/install; G drop; F flashlight; 1-0 hotbar; Esc menu."
Write-Host "Stop: .\STOP_M7_NETWORKED_PLAYGROUND.ps1"
