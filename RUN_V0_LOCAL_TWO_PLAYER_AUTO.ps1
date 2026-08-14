param(
    [string]$GodotPath = "",
    [string]$ServerAddress = "127.0.0.1",
    [ValidateRange(640, 3840)][int]$ClientWidth = 900,
    [ValidateRange(360, 2160)][int]$ClientHeight = 600,
    [ValidateRange(1024, 65535)][int]$PreferredPort = 24580,
    [ValidateRange(1, 100)][int]$ProbeCount = 40,
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root "RUN_V0_LOCAL_TWO_PLAYER.ps1"

if (-not (Test-Path $Launcher)) {
    throw "Base V0 local launcher was not found: $Launcher"
}

function Test-UdpPortAvailable {
    param([int]$Port)

    $Socket = $null
    try {
        $Socket = New-Object System.Net.Sockets.Socket -ArgumentList @(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp
        )
        $Socket.ExclusiveAddressUse = $true
        $EndPoint = New-Object System.Net.IPEndPoint -ArgumentList @(
            [System.Net.IPAddress]::Any,
            $Port
        )
        $Socket.Bind($EndPoint)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $Socket) {
            $Socket.Dispose()
        }
    }
}

$SelectedPort = 0
$LastPort = [Math]::Min(65535, $PreferredPort + $ProbeCount - 1)
for ($Candidate = $PreferredPort; $Candidate -le $LastPort; $Candidate++) {
    if (Test-UdpPortAvailable -Port $Candidate) {
        $SelectedPort = $Candidate
        break
    }
}

if ($SelectedPort -eq 0) {
    throw "No free UDP port was found in range $PreferredPort-$LastPort. Close stale Godot/server processes or choose another -PreferredPort."
}

if ($SelectedPort -ne $PreferredPort) {
    Write-Host "UDP port $PreferredPort is unavailable; using free port $SelectedPort." -ForegroundColor Yellow
}
else {
    Write-Host "UDP port $SelectedPort is available." -ForegroundColor Green
}

$Arguments = @{
    GodotPath = $GodotPath
    ServerAddress = $ServerAddress
    Port = $SelectedPort
    ClientWidth = $ClientWidth
    ClientHeight = $ClientHeight
}
if ($SkipImport) {
    $Arguments["SkipImport"] = $true
}

& $Launcher @Arguments
