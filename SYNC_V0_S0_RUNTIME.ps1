[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Get-Location).Path
}
Set-Location $ProjectRoot

if (-not (Test-Path (Join-Path $ProjectRoot ".git"))) {
    throw "Run this script from the distributed-world-simulator repository root."
}

$DeliveryRef = "origin/agent/v0-s1-inventory-convergence"
$DirectFiles = @(
    "RUN_V0_MVP.ps1",
    "scripts/actors/earth/earth_explorer.gd",
    "scripts/ui/planetary_overlay.gd",
    "scripts/network/realtime/realtime_channel_policy.gd",
    "patches/v0-s0-nx4-transport-direct.patch"
)
$PatchTargets = @(
    "scripts/network/transports/v2/enet_multi_peer_transport_port.gd",
    "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
)

Write-Host "[V0-S0] Fetching delivery ref..." -ForegroundColor Cyan
& git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw "git fetch origin failed."
}

# Do not silently overwrite local work on the stabilization-owned surfaces.
foreach ($Path in @($DirectFiles + $PatchTargets)) {
    if ($Path -like "patches/*" -or $Path -eq "RUN_V0_MVP.ps1") {
        continue
    }
    & git diff --quiet -- $Path
    if ($LASTEXITCODE -eq 1) {
        throw "Local modifications exist in stabilization-owned file: $Path. Refusing to overwrite it."
    }
    if ($LASTEXITCODE -gt 1) {
        throw "Unable to inspect local diff for: $Path"
    }
}

Write-Host "[V0-S0] Restoring direct camera/HUD/policy sources..."
$RestoreArgs = @("restore", "--source=$DeliveryRef", "--worktree", "--") + $DirectFiles
& git @RestoreArgs
if ($LASTEXITCODE -ne 0) {
    throw "Unable to restore direct V0-S0 source set from $DeliveryRef."
}

$PatchPath = Join-Path $ProjectRoot "patches\v0-s0-nx4-transport-direct.patch"
Write-Host "[V0-S0] Checking ENet/NX4 patch..."
& git apply --check -- $PatchPath
if ($LASTEXITCODE -ne 0) {
    throw "ENet/NX4 patch does not match the current clean transport/runtime files. Nothing was applied to those two files."
}

Write-Host "[V0-S0] Applying ENet/NX4 patch..."
& git apply -- $PatchPath
if ($LASTEXITCODE -ne 0) {
    throw "ENet/NX4 patch application failed."
}

& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed after V0-S0 sync."
}

$Markers = @(
    @{ Path = "scripts/actors/earth/earth_explorer.gd"; Text = "_network_surface_view_initialized"; Name = "camera" },
    @{ Path = "scripts/ui/planetary_overlay.gd"; Text = "_overlay_visible: bool = false"; Name = "HUD hidden" },
    @{ Path = "scripts/network/realtime/realtime_channel_policy.gd"; Text = "ENET_UNRELIABLE_ORDERED_APPLICATION_SEQUENCED_V1"; Name = "realtime policy" },
    @{ Path = "scripts/network/transports/v2/enet_multi_peer_transport_port.gd"; Text = "TRANSFER_MODE_UNRELIABLE_ORDERED"; Name = "ENet mapping" },
    @{ Path = "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"; Text = "disconnected_this_poll"; Name = "disconnect guard" },
    @{ Path = "scripts/app/earth_mvp_app.gd"; Text = "advance_local_prediction"; Name = "NX4 prediction" }
)

foreach ($Marker in $Markers) {
    $Found = Select-String -Path (Join-Path $ProjectRoot $Marker.Path) -SimpleMatch $Marker.Text -Quiet
    if (-not $Found) {
        throw "Required V0-S0 marker missing after sync: $($Marker.Name) [$($Marker.Path)]"
    }
}

$Branch = (& git branch --show-current).Trim()
$Head = (& git rev-parse --short=12 HEAD).Trim()
Write-Host ""
Write-Host "[V0-S0] PASS - runtime stabilization source set is installed." -ForegroundColor Green
Write-Host "  local branch : $Branch"
Write-Host "  local HEAD   : $Head"
Write-Host "  HUD          : hidden by default; F1 toggles it"
Write-Host "  camera       : scalar surface yaw/pitch; roll-free rebuild"
Write-Host "  movement     : NX4 prediction remains active"
Write-Host "  transport    : ENet unreliable ordered + application sequencing"
Write-Host "  timeout      : no false CONNECT_TIMEOUT after real disconnect"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Next: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
