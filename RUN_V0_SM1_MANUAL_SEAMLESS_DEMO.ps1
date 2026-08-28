param(
    [string]$GodotPath = "",
    [int]$GatewayPort = 0,
    [int]$AuthorityAPort = 0,
    [int]$AuthorityBPort = 0
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"

$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot.windows.editor.double.x86_64.exe", "godot4", "godot")) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $Command) { $Candidates += $Command.Source }
}
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $Godot) { throw "Double-precision Godot not found. Set GODOT_BIN or pass -GodotPath." }
$Godot = (Resolve-Path $Godot).Path
$ActualGodot = (& $Godot --version | Select-Object -First 1).Trim()
if ($ActualGodot -ne $ExpectedGodot) { throw "Godot version mismatch. Expected $ExpectedGodot, got $ActualGodot" }

function Get-FreeUdpPort {
    param([int[]]$Excluded = @())
    for ($Attempt = 0; $Attempt -lt 100; $Attempt++) {
        $Udp = New-Object System.Net.Sockets.UdpClient(0)
        try {
            $Port = ([System.Net.IPEndPoint]$Udp.Client.LocalEndPoint).Port
        }
        finally { $Udp.Close() }
        if ($Port -notin $Excluded) { return $Port }
    }
    throw "Unable to allocate a free UDP port"
}
if ($AuthorityAPort -le 0) { $AuthorityAPort = Get-FreeUdpPort }
if ($AuthorityBPort -le 0) { $AuthorityBPort = Get-FreeUdpPort -Excluded @($AuthorityAPort) }
if ($GatewayPort -le 0) { $GatewayPort = Get-FreeUdpPort -Excluded @($AuthorityAPort, $AuthorityBPort) }

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ResultRoot = Join-Path $Root "artifacts\test-results\sm1-manual-demo-$Stamp"
New-Item -ItemType Directory -Force -Path $ResultRoot | Out-Null

function Read-State {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return (Get-Content $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
function Wait-State {
    param([string]$Path, [string[]]$States, [int]$TimeoutMs = 15000)
    $Watch = [Diagnostics.Stopwatch]::StartNew()
    while ($Watch.ElapsedMilliseconds -le $TimeoutMs) {
        $Value = Read-State $Path
        if ($null -ne $Value -and $Value.state -in $States) { return $Value }
        Start-Sleep -Milliseconds 100
    }
    return (Read-State $Path)
}

$EnvNames = @("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "BREAKPOINT_RUNTIME_DISABLED", "GODOT_SILENCE_ROOT_WARNING")
function Start-GodotChild {
    param([string]$Name, [string[]]$Arguments)
    $UserRoot = Join-Path $ResultRoot "profile-$Name"
    $Data = Join-Path $UserRoot "data"
    $Config = Join-Path $UserRoot "config"
    $Cache = Join-Path $UserRoot "cache"
    foreach ($Path in @($UserRoot, $Data, $Config, $Cache)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    $Saved = @{}
    foreach ($EnvName in $EnvNames) { $Saved[$EnvName] = [Environment]::GetEnvironmentVariable($EnvName, "Process") }
    try {
        $env:HOME = $UserRoot; $env:USERPROFILE = $UserRoot
        $env:APPDATA = $Data; $env:LOCALAPPDATA = $Data
        $env:XDG_DATA_HOME = $Data; $env:XDG_CONFIG_HOME = $Config; $env:XDG_CACHE_HOME = $Cache
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $env:GODOT_SILENCE_ROOT_WARNING = "1"
        return Start-Process -FilePath $Godot -ArgumentList $Arguments -WorkingDirectory $Root -PassThru
    }
    finally {
        foreach ($EnvName in $EnvNames) {
            [Environment]::SetEnvironmentVariable($EnvName, $Saved[$EnvName], "Process")
        }
    }
}

$AuthorityAResult = Join-Path $ResultRoot "authority-a.json"
$AuthorityBResult = Join-Path $ResultRoot "authority-b.json"
$GatewayResult = Join-Path $ResultRoot "gateway.json"
$ClientResult = Join-Path $ResultRoot "client.json"
$Processes = @()

try {
    Write-Host "SM1 manual seamless demo" -ForegroundColor Cyan
    Write-Host "Godot: $ActualGodot"
    Write-Host "Authority A: 127.0.0.1:$AuthorityAPort"
    Write-Host "Authority B: 127.0.0.1:$AuthorityBPort"
    Write-Host "Gateway:     127.0.0.1:$GatewayPort  <-- client connects ONLY here" -ForegroundColor Yellow
    Write-Host "Artifacts:   $ResultRoot"

    $Processes += Start-GodotChild "authority-a" @(
        "--headless", "--log-file", (Join-Path $ResultRoot "authority-a.log"), "--path", $Root,
        "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
        "--authority-id=authority/a", "--host=127.0.0.1", "--port=$AuthorityAPort",
        "--initial-active=true", "--initial-epoch=1", "--result-file=$AuthorityAResult", "--timeout-ms=86400000"
    )
    $Processes += Start-GodotChild "authority-b" @(
        "--headless", "--log-file", (Join-Path $ResultRoot "authority-b.log"), "--path", $Root,
        "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
        "--authority-id=authority/b", "--host=127.0.0.1", "--port=$AuthorityBPort",
        "--initial-active=false", "--initial-epoch=1", "--result-file=$AuthorityBResult", "--timeout-ms=86400000"
    )
    $AState = Wait-State $AuthorityAResult @("LISTENING", "FAILED")
    $BState = Wait-State $AuthorityBResult @("LISTENING", "FAILED")
    if ($null -eq $AState -or $AState.state -ne "LISTENING") { throw "Authority A failed to listen. See $ResultRoot\authority-a.log" }
    if ($null -eq $BState -or $BState.state -ne "LISTENING") { throw "Authority B failed to listen. See $ResultRoot\authority-b.log" }

    $Processes += Start-GodotChild "gateway" @(
        "--headless", "--log-file", (Join-Path $ResultRoot "gateway.log"), "--path", $Root,
        "--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_gateway_worker.gd", "--",
        "--client-host=127.0.0.1", "--client-port=$GatewayPort",
        "--authority-a-host=127.0.0.1", "--authority-a-port=$AuthorityAPort",
        "--authority-b-host=127.0.0.1", "--authority-b-port=$AuthorityBPort",
        "--demo-mode=true", "--required-client-count=1", "--result-file=$GatewayResult", "--timeout-ms=86400000"
    )
    $GState = Wait-State $GatewayResult @("LISTENING", "FAILED")
    if ($null -eq $GState -or $GState.state -ne "LISTENING") { throw "Gateway failed to listen. See $ResultRoot\gateway.log" }

    Write-Host ""
    Write-Host "Controls:" -ForegroundColor Green
    Write-Host "  W / D / Right  -> move toward Authority B"
    Write-Host "  S / A / Left   -> move toward Authority A"
    Write-Host "  Esc            -> gracefully stop after the A -> B -> A demonstration"
    Write-Host ""

    $ClientUser = Join-Path $ResultRoot "profile-client"
    $ClientData = Join-Path $ClientUser "data"; $ClientConfig = Join-Path $ClientUser "config"; $ClientCache = Join-Path $ClientUser "cache"
    foreach ($Path in @($ClientUser, $ClientData, $ClientConfig, $ClientCache)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
    $SavedClientEnv = @{}
    foreach ($EnvName in $EnvNames) { $SavedClientEnv[$EnvName] = [Environment]::GetEnvironmentVariable($EnvName, "Process") }
    try {
        $env:HOME = $ClientUser; $env:USERPROFILE = $ClientUser
        $env:APPDATA = $ClientData; $env:LOCALAPPDATA = $ClientData
        $env:XDG_DATA_HOME = $ClientData; $env:XDG_CONFIG_HOME = $ClientConfig; $env:XDG_CACHE_HOME = $ClientCache
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"; $env:GODOT_SILENCE_ROOT_WARNING = "1"
        & $Godot "--log-file" (Join-Path $ResultRoot "client.log") "--path" $Root "--rendering-method" "gl_compatibility" `
            "--script" "res://scripts/runtime/networked_gameplay/sm1/sm1_manual_seamless_client.gd" "--" `
            "--host=127.0.0.1" "--port=$GatewayPort" "--result-file=$ClientResult" "--timeout-ms=86400000"
        $ClientExit = $LASTEXITCODE
    }
    finally {
        foreach ($EnvName in $EnvNames) { [Environment]::SetEnvironmentVariable($EnvName, $SavedClientEnv[$EnvName], "Process") }
    }

    Start-Sleep -Milliseconds 1200
    $ClientReport = Read-State $ClientResult
    $GatewayReport = Read-State $GatewayResult
    if ($ClientExit -ne 0 -or $null -eq $ClientReport -or -not $ClientReport.passed) {
        throw "Manual client did not complete the seamless A->B->A goal. See $ResultRoot\client.log"
    }
    if ($null -eq $GatewayReport -or -not $GatewayReport.passed) {
        throw "Gateway did not close cleanly. See $ResultRoot\gateway.log"
    }
    Write-Host ""
    Write-Host "SM1_MANUAL_SEAMLESS_DEMO_PASS" -ForegroundColor Green
    Write-Host "route: $($ClientReport.route_history -join ' -> ')"
    Write-Host "epochs: $($ClientReport.epochs -join ' -> ')"
    Write-Host "connect_count=$($ClientReport.connect_count) reconnect_count=$($ClientReport.reconnect_count) respawn_count=$($ClientReport.respawn_count)"
    Write-Host "Gateway endpoint: $($ClientReport.gateway_endpoint_id)"
    Write-Host "Report: $ClientResult"
}
finally {
    foreach ($Process in $Processes) {
        if ($null -ne $Process -and -not $Process.HasExited) {
            try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}
