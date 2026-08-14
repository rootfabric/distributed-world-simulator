[CmdletBinding()]
param(
    [ValidateRange(0, 32)]
    [int]$Clients = 2,

    [ValidateRange(1024, 65535)]
    [int]$PreferredPort = 24580,

    [ValidateRange(1, 100)]
    [int]$ProbeCount = 40,

    [string]$ServerAddress = "127.0.0.1",
    [string]$World = "earth",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "",
    [switch]$Restart,
    [switch]$AllowUnstabilized
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root "RUN_V0_MVP.ps1"

if (-not (Test-Path $Launcher)) {
    throw "Recovered V0 MVP launcher not found: $Launcher"
}

function Test-UdpPortAvailable {
    param([int]$Port)
    $Socket = $null
    try {
        $Socket = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp
        )
        $Socket.ExclusiveAddressUse = $true
        $Socket.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)))
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $Socket) { $Socket.Dispose() }
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
    throw "No free UDP port found in range $PreferredPort-$LastPort. Stop stale Godot/server processes or choose another -PreferredPort."
}

if ($SelectedPort -eq $PreferredPort) {
    Write-Host "[V0] UDP port $SelectedPort is available." -ForegroundColor Green
}
else {
    Write-Host "[V0] UDP port $PreferredPort is unavailable; using $SelectedPort." -ForegroundColor Yellow
}

$Arguments = @{
    Clients = $Clients
    Port = $SelectedPort
    ServerAddress = $ServerAddress
    World = $World
    GodotExe = $GodotExe
}
if (-not [string]::IsNullOrWhiteSpace($GodotGuiExe)) {
    $Arguments["GodotGuiExe"] = $GodotGuiExe
}
if ($Restart) { $Arguments["Restart"] = $true }
if ($AllowUnstabilized) { $Arguments["AllowUnstabilized"] = $true }

& $Launcher @Arguments
exit $LASTEXITCODE
