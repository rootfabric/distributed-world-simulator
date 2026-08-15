[CmdletBinding()]
param(
    [ValidateRange(0, 32)]
    [int]$Clients = 2,

    [ValidateRange(1024, 65535)]
    [int]$PreferredPort = 24580,

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManagedLauncher = Join-Path $Root "RUN_V0_MVP.ps1"
$SyncI1 = Join-Path $Root "SYNC_V0_I1_RECOVERY.ps1"
$SyncS0 = Join-Path $Root "SYNC_V0_S0_RUNTIME.ps1"
$SyncI2C1 = Join-Path $Root "SYNC_V0_I2_C1_RUNTIME.ps1"
$AutoLauncher = Join-Path $Root "RUN_V0_MVP_AUTO.ps1"

foreach ($Required in @($ManagedLauncher, $SyncI1, $SyncS0, $SyncI2C1, $AutoLauncher)) {
    if (-not (Test-Path $Required)) {
        throw "Recovered V0 prerequisite is missing: $Required"
    }
}
if (-not (Test-Path $GodotExe)) {
    throw "Godot console executable not found: $GodotExe"
}

Write-Host "[RECOVERY 1/5] Stopping any previous managed V0 session..." -ForegroundColor Cyan
& $ManagedLauncher -Stop
if ($LASTEXITCODE -ne 0) {
    throw "Unable to stop previous managed V0 session."
}

Write-Host "[RECOVERY 2/5] Restoring historical V0-I1 prerequisite stack..." -ForegroundColor Cyan
Write-Host "  - cumulative Tab/spawn/spectator + M5 inventory convergence"
Write-Host "  - reliable camera-relative SERVER_PREDICTED movement fallback"
Write-Host "  - gameplay mouse-capture fix"
& $SyncI1
if ($LASTEXITCODE -ne 0) {
    throw "V0-I1 prerequisite recovery failed."
}

Write-Host "[RECOVERY 3/5] Restoring the proven V0-S0 runtime stabilization..." -ForegroundColor Cyan
Write-Host "  - surface-locked camera + hidden F1 HUD"
Write-Host "  - ordered ENet realtime mapping"
Write-Host "  - disconnect timeout guard"
Write-Host "  - explicit gameplay/inventory input ownership"
& $SyncS0
if ($LASTEXITCODE -ne 0) {
    throw "V0-S0 recovery sync failed."
}

Write-Host "[RECOVERY 4/5] Restoring the proven local I2/C1 playable composition..." -ForegroundColor Cyan
Write-Host "  - 7DTD inventory click/place fix"
Write-Host "  - Construction session plumbing"
Write-Host "  - Inventory build controls"
Write-Host "  - Earth Construction observer frame"
& $SyncI2C1 -GodotExe $GodotExe
if ($LASTEXITCODE -ne 0) {
    throw "V0 I2/C1 recovery sync or focused validation failed."
}

Write-Host "[RECOVERY 5/5] Launching recovered playable MVP..." -ForegroundColor Cyan
$LaunchArgs = @{
    Clients = $Clients
    PreferredPort = $PreferredPort
    GodotExe = $GodotExe
}
if (-not [string]::IsNullOrWhiteSpace($GodotGuiExe)) {
    $LaunchArgs["GodotGuiExe"] = $GodotGuiExe
}
& $AutoLauncher @LaunchArgs
exit $LASTEXITCODE
