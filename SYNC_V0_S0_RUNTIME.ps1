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
$DeliveryFiles = @(
    "patches/v0-s0-nx4-transport-direct.patch",
    "patches/v0-s0-input-ownership-direct.patch"
)
$DirectProductionFiles = @(
    "RUN_V0_MVP.ps1",
    "scripts/actors/earth/earth_explorer.gd",
    "scripts/ui/planetary_overlay.gd",
    "scripts/network/realtime/realtime_channel_policy.gd"
)
$NxPatchTargets = @(
    "scripts/network/transports/v2/enet_multi_peer_transport_port.gd",
    "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
)

function Test-Marker {
    param(
        [string]$RelativePath,
        [string]$Text
    )
    $Path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path $Path)) {
        return $false
    }
    return [bool](Select-String -Path $Path -SimpleMatch $Text -Quiet)
}

Write-Host "[V0-S0] Fetching delivery ref..." -ForegroundColor Cyan
& git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw "git fetch origin failed."
}

# Delivery artifacts are not production source. Always refresh them so stale
# V1/V2/V3 copies cannot affect this sync.
$ArtifactRestoreArgs = @("restore", "--source=$DeliveryRef", "--worktree", "--") + $DeliveryFiles
& git @ArtifactRestoreArgs
if ($LASTEXITCODE -ne 0) {
    throw "Unable to restore V0-S0 delivery artifacts from $DeliveryRef."
}

$NxTransportInstalled = Test-Marker `
    "scripts/network/transports/v2/enet_multi_peer_transport_port.gd" `
    "TRANSFER_MODE_UNRELIABLE_ORDERED"
$DisconnectGuardInstalled = Test-Marker `
    "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd" `
    "disconnected_this_poll"

if ($NxTransportInstalled -xor $DisconnectGuardInstalled) {
    throw "Partial ENet/NX4 stabilization detected. Refusing to stack another patch over an inconsistent network runtime."
}
$NxAlreadyApplied = $NxTransportInstalled -and $DisconnectGuardInstalled

$EarthMvpPath = Join-Path $ProjectRoot "scripts\app\earth_mvp_app.gd"
$InventoryShellPath = Join-Path $ProjectRoot "scripts\ui\inventory\networked\m5_networked_inventory_shell.gd"
$InputOwnershipAlreadyApplied = (
    (Select-String -Path $EarthMvpPath -SimpleMatch '_mvp_input_owner' -Quiet) -and
    -not (Select-String -Path $InventoryShellPath -SimpleMatch 'Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED' -Quiet)
)

$NxPatchPath = Join-Path $ProjectRoot "patches\v0-s0-nx4-transport-direct.patch"
$InputPatchPath = Join-Path $ProjectRoot "patches\v0-s0-input-ownership-direct.patch"

if ($NxAlreadyApplied) {
    Write-Host "[V0-S0] ENet/NX4 stabilization already installed; skipping its patch."
}
else {
    foreach ($Path in $NxPatchTargets) {
        & git diff --quiet -- $Path
        if ($LASTEXITCODE -eq 1) {
            throw "Local modifications exist in network stabilization target: $Path. Refusing to patch it."
        }
        if ($LASTEXITCODE -gt 1) {
            throw "Unable to inspect local diff for: $Path"
        }
    }

    Write-Host "[V0-S0] Prechecking ENet/NX4 patch..."
    & git apply --check -- $NxPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "ENet/NX4 patch does not match the current clean transport/runtime files."
    }
}

if ($InputOwnershipAlreadyApplied) {
    Write-Host "[V0-S0] Input ownership already installed; skipping its patch."
}
else {
    Write-Host "[V0-S0] Prechecking input-ownership patch against local convergence files..."
    & git apply --check -- $InputPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Input-ownership patch does not match the current local MVP/inventory convergence files."
    }
}

# These four files are the direct V0-S0 presentation/policy delivery. Restore
# them exactly from the delivery branch. This is intentionally idempotent and
# also completes a previous sync that stopped after this step.
Write-Host "[V0-S0] Synchronizing camera/HUD/policy/launcher sources..."
$DirectRestoreArgs = @("restore", "--source=$DeliveryRef", "--worktree", "--") + $DirectProductionFiles
& git @DirectRestoreArgs
if ($LASTEXITCODE -ne 0) {
    throw "Unable to restore direct V0-S0 production source set from $DeliveryRef."
}

if (-not $NxAlreadyApplied) {
    Write-Host "[V0-S0] Applying ENet/NX4 patch..."
    & git apply -- $NxPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "ENet/NX4 patch application failed."
    }
}

if (-not $InputOwnershipAlreadyApplied) {
    Write-Host "[V0-S0] Applying input-ownership patch..."
    & git apply -- $InputPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Input-ownership patch application failed."
    }
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
    @{ Path = "scripts/app/earth_mvp_app.gd"; Text = "advance_local_prediction"; Name = "NX4 prediction" },
    @{ Path = "scripts/app/earth_mvp_app.gd"; Text = "_mvp_input_owner"; Name = "input ownership" },
    @{ Path = "RUN_V0_MVP.ps1"; Text = "Assert-V0StabilizedSource"; Name = "launcher source gate" }
)

foreach ($Marker in $Markers) {
    if (-not (Test-Marker $Marker.Path $Marker.Text)) {
        throw "Required V0-S0 marker missing after sync: $($Marker.Name) [$($Marker.Path)]"
    }
}

# `git branch --show-current` intentionally produces no output in a detached
# checkout. PowerShell represents that as $null, so calling .Trim() directly
# used to turn a successful S0 sync into InvokeMethodOnNull. A detached checkout
# is valid for this recovery harness; normalize it to an explicit diagnostic.
$BranchOutput = @(& git branch --show-current)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect current git branch after V0-S0 sync."
}
$Branch = (($BranchOutput -join "`n").Trim())
if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = "(detached HEAD)"
}

$HeadOutput = @(& git rev-parse --short=12 HEAD)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve current HEAD after V0-S0 sync."
}
$Head = (($HeadOutput -join "`n").Trim())
if ([string]::IsNullOrWhiteSpace($Head)) {
    throw "git rev-parse returned an empty HEAD after V0-S0 sync."
}

Write-Host ""
Write-Host "[V0-S0] PASS - runtime stabilization source set is installed." -ForegroundColor Green
Write-Host "  local branch : $Branch"
Write-Host "  local HEAD   : $Head"
Write-Host "  HUD          : fully hidden by default; F1 toggles it"
Write-Host "  camera       : scalar surface yaw/pitch; roll-free rebuild"
Write-Host "  input        : explicit gameplay/inventory ownership"
Write-Host "  movement     : NX4 prediction remains active"
Write-Host "  transport    : ENet unreliable ordered + application sequencing"
Write-Host "  timeout      : no false CONNECT_TIMEOUT after real disconnect"
Write-Host "  launcher     : refuses stale/partial V0 source trees"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Next: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
