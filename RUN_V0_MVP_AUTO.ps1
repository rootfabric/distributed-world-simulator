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
    [switch]$AllowUnstabilized,
    [switch]$SkipProjectPreflight
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Launcher = Join-Path $Root "RUN_V0_MVP.ps1"

if (-not (Test-Path $Launcher)) {
    throw "Recovered V0 MVP launcher not found: $Launcher"
}
if (-not (Test-Path $GodotExe)) {
    throw "Godot console executable not found: $GodotExe"
}

function Invoke-ProjectPreflight {
    $PreflightRoot = Join-Path $Root "artifacts\runtime\v0-recovery-preflight"
    New-Item -ItemType Directory -Force -Path $PreflightRoot | Out-Null
    $BootstrapLog = Join-Path $PreflightRoot "bootstrap.log"
    $VerifyLog = Join-Path $PreflightRoot "verify.log"

    Write-Host "[V0] Preparing Godot UID/script-class cache for this checkout..." -ForegroundColor Cyan
    & $GodotExe --headless --editor --path $Root --log-file $BootstrapLog --quit-after 1
    if ($LASTEXITCODE -ne 0) {
        throw "Godot project metadata bootstrap failed. See $BootstrapLog"
    }

    # A clean worktree has no tracked .godot cache. Run a second editor pass so
    # UID autoloads and class_name dependencies are verified after the cache was
    # populated by the bootstrap pass.
    & $GodotExe --headless --editor --path $Root --log-file $VerifyLog --quit-after 1
    if ($LASTEXITCODE -ne 0) {
        throw "Godot project preflight failed. See $VerifyLog"
    }

    $FatalPatterns = @(
        "SCRIPT ERROR:",
        "Failed to instantiate an autoload",
        "Resource file not found: res://",
        "Failed to load script"
    )
    foreach ($Pattern in $FatalPatterns) {
        if (Select-String -Path $VerifyLog -SimpleMatch $Pattern -Quiet) {
            Write-Host "[V0] Project preflight detected a fatal startup/compiler error:" -ForegroundColor Red
            Get-Content $VerifyLog -Tail 120
            throw "Recovered V0 checkout is not parser-clean after metadata bootstrap. See $VerifyLog"
        }
    }
    Write-Host "[V0] Project preflight: parser/autoload cache ready." -ForegroundColor Green
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

if (-not $SkipProjectPreflight) {
    Invoke-ProjectPreflight
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
