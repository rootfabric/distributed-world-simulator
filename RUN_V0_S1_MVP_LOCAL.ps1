param(
    [int]$ClientCount = 2,
    [int]$Port = 24580
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($ClientCount -lt 1 -or $ClientCount -gt 2) {
    throw "ClientCount must be 1 or 2 for the V0-S1 MVP."
}
if ($Port -lt 1 -or $Port -gt 65535) {
    throw "Port must be in range 1..65535."
}

$Candidates = @($env:GODOT_BIN)
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Godot) {
    throw "Double-precision Godot was not found. Set GODOT_BIN or build it in C:\Godot\godot\bin."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogRoot = Join-Path $Root "artifacts\mvp-local\$Timestamp"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$GodotVersion = (& $Godot --version 2>&1 | Out-String).Trim()
$GitHead = (& git -C $Root rev-parse HEAD 2>&1 | Out-String).Trim()
$GodotVersion | Set-Content -Encoding UTF8 (Join-Path $LogRoot "godot-version.txt")
$GitHead | Set-Content -Encoding UTF8 (Join-Path $LogRoot "git-head.txt")

function Start-MvpProcess {
    param(
        [string]$Name,
        [string[]]$Arguments
    )
    $Stdout = Join-Path $LogRoot "$Name.stdout.log"
    $Stderr = Join-Path $LogRoot "$Name.stderr.log"
    $Process = Start-Process `
        -FilePath $Godot `
        -ArgumentList $Arguments `
        -WorkingDirectory $Root `
        -RedirectStandardOutput $Stdout `
        -RedirectStandardError $Stderr `
        -PassThru
    return [PSCustomObject]@{
        Name = $Name
        Pid = $Process.Id
        Process = $Process
        Stdout = $Stdout
        Stderr = $Stderr
    }
}

$CommonNetworkArgs = @(
    "--world=earth",
    "--network-mvp",
    "--network-debug",
    "--print-runtime-descriptor",
    "--server-address=127.0.0.1",
    "--server-port=$Port",
    "--network-profile=LOCAL"
)

$ServerArgs = @(
    "--headless",
    "--path", $Root,
    "--",
    "--role=dedicated-server",
    "--node-id=v0-s1-mvp-server",
    "--m6-persistence-root=user://v0-s1-mvp-persistence"
) + $CommonNetworkArgs

$Processes = @()
$Processes += Start-MvpProcess -Name "server" -Arguments $ServerArgs
Start-Sleep -Seconds 2

$ClientIds = @("a", "b")
for ($Index = 0; $Index -lt $ClientCount; $Index++) {
    $ClientId = $ClientIds[$Index]
    $ClientArgs = @(
        "--path", $Root,
        "--",
        "--role=game-client",
        "--node-id=v0-s1-mvp-client-$ClientId",
        "--player-identity=$ClientId",
        "--network-debug-stay-open"
    ) + $CommonNetworkArgs
    $Processes += Start-MvpProcess -Name "client-$ClientId" -Arguments $ClientArgs
    Start-Sleep -Milliseconds 500
}

$PidFile = Join-Path $LogRoot "processes.json"
$Processes | ForEach-Object {
    [PSCustomObject]@{
        name = $_.Name
        pid = $_.Pid
        stdout = $_.Stdout
        stderr = $_.Stderr
    }
} | ConvertTo-Json | Set-Content -Encoding UTF8 $PidFile

$LatestFile = Join-Path $Root "artifacts\mvp-local\LATEST.txt"
$LogRoot | Set-Content -Encoding UTF8 $LatestFile

Write-Host ""
Write-Host "V0-S1 MVP started." -ForegroundColor Green
Write-Host "Godot: $GodotVersion"
Write-Host "Git HEAD: $GitHead"
Write-Host "Logs: $LogRoot"
foreach ($Entry in $Processes) {
    Write-Host ("  {0,-10} PID {1}" -f $Entry.Name, $Entry.Pid)
}
Write-Host ""
Write-Host "Expected client HUD: СЕТЬ: authoritative replica, stable MVP X/Z coordinates."
Write-Host "Expected input: mouse-look stays local; WASD is sent through the server."
Write-Host "To inspect live logs:"
Write-Host "  Get-Content -Wait `"$(Join-Path $LogRoot 'client-a.stdout.log')`""
Write-Host "  Get-Content -Wait `"$(Join-Path $LogRoot 'server.stdout.log')`""
Write-Host ""
Write-Host "To stop all processes started by this run:"
$PidList = ($Processes | ForEach-Object { $_.Pid }) -join ","
Write-Host "  Stop-Process -Id $PidList"
