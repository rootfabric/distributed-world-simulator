param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [string]$SessionId = "manual",
    [string]$ServerAddress = "127.0.0.1",
    [ValidateRange(1, 65535)][int]$Port = 24580,
    [ValidateSet("LOCAL","GOOD_BROADBAND","AVERAGE_BROADBAND","MOBILE","BAD_MOBILE","EXTREME","LAG_SPIKE","ASYMMETRIC")][string]$NetworkProfile = "LOCAL",
    [string]$NetworkPresetsFile = "res://config/network/network-condition-presets.v1.json",
    [string]$PersistenceRoot = "",
    [switch]$ResetPersistence
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path
$NetworkSessionId = ($SessionId.ToLowerInvariant() -replace '[^a-z0-9._-]', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($NetworkSessionId)) { $NetworkSessionId = 'manual' }
$NetworkSessionToken = "session-id/m7-debug-$NetworkSessionId"
$RunRoot = Join-Path $ProjectRoot "artifacts/runtime/m7-network-debug/$SessionId"
$RoleRoot = Join-Path $RunRoot "server"
$ProfileRoot = Join-Path $RoleRoot "profile"
$LogPath = Join-Path $RoleRoot "godot.log"
$ResultPath = Join-Path $RoleRoot "server-state.json"
$ProcessPath = Join-Path $RoleRoot "process.json"
if ([string]::IsNullOrWhiteSpace($PersistenceRoot)) {
    $PersistenceRoot = Join-Path $ProjectRoot "artifacts/runtime/m7-network-debug-persistence/$SessionId"
}
if ($ResetPersistence -and (Test-Path $PersistenceRoot)) {
    Remove-Item $PersistenceRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $RoleRoot,$ProfileRoot,$PersistenceRoot | Out-Null
Remove-Item $LogPath,$ResultPath,$ProcessPath -Force -ErrorAction SilentlyContinue

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
    "--headless","--path",$ProjectRoot,"--log-file",$LogPath,"--",
    "--role=dedicated-server","--network-playground","--network-debug","--world=playground",
    "--network-session-token=$NetworkSessionToken",
    "--node-id=m7-debug-server","--instance-id=m7-debug-$SessionId",
    "--server-address=$ServerAddress","--server-port=$Port",
    "--network-profile=$NetworkProfile","--network-presets-file=$NetworkPresetsFile",
    "--m7-result-file=$ResultPath","--m6-persistence-root=$PersistenceRoot",
    "--print-runtime-descriptor"
)

Write-Host "M7 dedicated server" -ForegroundColor Cyan
Write-Host "Session:     $SessionId"
Write-Host "Endpoint:    $ServerAddress`:$Port"
Write-Host "Log:         $LogPath"
Write-Host "State:       $ResultPath"
Write-Host "Persistence: $PersistenceRoot"
Write-Host "Net profile: $NetworkProfile (server endpoint only)"
Write-Host "Stop with Ctrl+C or .\STOP_M7_NETWORK_DEBUG.ps1 -SessionId $SessionId" -ForegroundColor Yellow

$Process = Start-IsolatedProcess -Executable $Godot -Arguments $Arguments -Profile $ProfileRoot
$Descriptor = [ordered]@{
    schema = "planet_simulator.m7_network_debug_process.v1"
    session_id = $SessionId
    network_session_token = $NetworkSessionToken
    role = "server"
    pid = $Process.Id
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    log_path = $LogPath
    result_path = $ResultPath
    persistence_root = $PersistenceRoot
    endpoint = "$ServerAddress`:$Port"
    network_profile = $NetworkProfile
    network_presets_file = $NetworkPresetsFile
    godot_path = $Godot
}
$Descriptor | ConvertTo-Json -Depth 5 | Set-Content -Path $ProcessPath -Encoding UTF8
try {
    $Process.WaitForExit()
    $Descriptor.exit_code = $Process.ExitCode
    $Descriptor.exited_at_utc = [DateTime]::UtcNow.ToString("o")
    $Descriptor | ConvertTo-Json -Depth 5 | Set-Content -Path $ProcessPath -Encoding UTF8
    Write-Host "Server exited with code $($Process.ExitCode). Log: $LogPath" -ForegroundColor Yellow
    exit $Process.ExitCode
}
finally {
    if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
}
