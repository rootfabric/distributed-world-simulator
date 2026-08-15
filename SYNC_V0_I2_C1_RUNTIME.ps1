[CmdletBinding()]
param(
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

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
$PatchFiles = @(
    "patches/v0-i2-fix-seven-days-cursor-placement.patch",
    "patches/v0-c1-construction-session-plumbing.patch",
    "patches/v0-c1-inventory-build-controls.patch",
    "patches/v0-c2-earth-construction-observer-frame.patch"
)
$DirectFiles = @(
    "scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd",
    "scripts/app/earth_construction_presentation.gd",
    "tests/runtime/test_v0_i2_inventory_click_place.gd",
    "tests/runtime/test_v0_c1_mvp_outpost_client_adapter.gd"
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

function Assert-Marker {
    param(
        [string]$RelativePath,
        [string]$Text,
        [string]$Name
    )
    if (-not (Test-Marker $RelativePath $Text)) {
        throw "Required marker missing: $Name [$RelativePath]"
    }
}

function Invoke-GitApplyCheck {
    param([string]$PatchPath)
    & git apply --check -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch does not match the current local convergence tree: $PatchPath"
    }
}

function Invoke-GitApply {
    param([string]$PatchPath)
    & git apply -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch application failed: $PatchPath"
    }
}

Write-Host "[V0-I2/C1] Fetching delivery ref..." -ForegroundColor Cyan
& git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw "git fetch origin failed."
}

# This slice is intentionally layered on the already working V0-S0 runtime.
$S0Markers = @(
    @{ Path = "scripts/actors/earth/earth_explorer.gd"; Text = "_network_surface_view_initialized"; Name = "surface camera" },
    @{ Path = "scripts/ui/planetary_overlay.gd"; Text = "_overlay_visible: bool = false"; Name = "hidden HUD" },
    @{ Path = "scripts/network/transports/v2/enet_multi_peer_transport_port.gd"; Text = "TRANSFER_MODE_UNRELIABLE_ORDERED"; Name = "ordered ENet" },
    @{ Path = "scripts/app/earth_mvp_app.gd"; Text = "_mvp_input_owner"; Name = "input ownership" },
    @{ Path = "scripts/app/earth_mvp_app.gd"; Text = "advance_local_prediction"; Name = "NX4 prediction" }
)
foreach ($Marker in $S0Markers) {
    Assert-Marker $Marker.Path $Marker.Text $Marker.Name
}

# Refresh only delivery patches. The caller explicitly restores this script
# before execution; a running PowerShell script must never rewrite itself.
$RestoreArtifacts = @("restore", "--source=$DeliveryRef", "--worktree", "--") + $PatchFiles
& git @RestoreArtifacts
if ($LASTEXITCODE -ne 0) {
    throw "Unable to restore V0-I2/C1 delivery artifacts."
}

$InventoryPlacementInstalled = Test-Marker `
    "scripts/ui/inventory/item_cell.gd" `
    "7DTD click-carry is atomic on press"
$BridgeSessionInstalled = Test-Marker `
    "scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd" `
    'snapshot_packet["client_session"]'
$ClientSessionInstalled = Test-Marker `
    "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd" `
    "func get_construction_session()"
$BuildControlsInstalled = Test-Marker `
    "scripts/ui/inventory/networked/m5_networked_inventory_shell.gd" `
    "MvpOutpostClientAdapter"
$LegacyObserverFrameInstalled = Test-Marker `
    "scripts/app/earth_app.gd" `
    "func _update_construction_observer_frame()"
$EarthFixedAnchorInstalled = (
    (Test-Marker "scripts/app/earth_app.gd" "func _update_construction_render_transform()") -and
    (Test-Marker "scripts/app/earth_app.gd" "EarthSurfaceRenderProjectorScript.project_anchor") -and
    (Test-Marker "scripts/app/earth_construction_presentation.gd" "func set_derived_render_transform")
)
$ConstructionFrameInstalled = $LegacyObserverFrameInstalled -or $EarthFixedAnchorInstalled

if ($BridgeSessionInstalled -xor $ClientSessionInstalled) {
    throw "Partial construction-session plumbing detected. Refusing to stack over inconsistent M3 state."
}
$SessionPlumbingInstalled = $BridgeSessionInstalled -and $ClientSessionInstalled

$InventoryPatch = Join-Path $ProjectRoot "patches\v0-i2-fix-seven-days-cursor-placement.patch"
$SessionPatch = Join-Path $ProjectRoot "patches\v0-c1-construction-session-plumbing.patch"
$ControlsPatch = Join-Path $ProjectRoot "patches\v0-c1-inventory-build-controls.patch"
$ObserverPatch = Join-Path $ProjectRoot "patches\v0-c2-earth-construction-observer-frame.patch"

# Fail closed before changing production files.
if (-not $InventoryPlacementInstalled) {
    Write-Host "[V0-I2/C1] Prechecking inventory click-place fix..."
    Invoke-GitApplyCheck $InventoryPatch
}
if (-not $SessionPlumbingInstalled) {
    Write-Host "[V0-I2/C1] Prechecking construction session plumbing..."
    Invoke-GitApplyCheck $SessionPatch
}
if (-not $BuildControlsInstalled) {
    Write-Host "[V0-I2/C1] Prechecking inventory construction controls..."
    Invoke-GitApplyCheck $ControlsPatch
}
if ($EarthFixedAnchorInstalled) {
    Write-Host "[V0-I2/C1] Earth-fixed Construction anchor already installed; legacy observer-frame patch is superseded."
}
elseif (-not $LegacyObserverFrameInstalled) {
    Write-Host "[V0-I2/C1] Prechecking Earth construction observer frame..."
    Invoke-GitApplyCheck $ObserverPatch
}

# Earth construction presentation is stabilization-owned and was clean before
# this slice. Refuse to overwrite an unrelated local edit there.
$PresentationPath = "scripts/app/earth_construction_presentation.gd"
if (-not (Test-Marker $PresentationPath "MVP_OUTPOST_PLANAR_POSITION")) {
    & git diff --quiet -- $PresentationPath
    if ($LASTEXITCODE -eq 1) {
        throw "Local modifications exist in $PresentationPath; refusing to overwrite them."
    }
    if ($LASTEXITCODE -gt 1) {
        throw "Unable to inspect local diff for $PresentationPath."
    }
}

Write-Host "[V0-I2/C1] Installing outpost adapter, C22/C24 presentation and focused tests..."
$RestoreDirect = @("restore", "--source=$DeliveryRef", "--worktree", "--") + $DirectFiles
& git @RestoreDirect
if ($LASTEXITCODE -ne 0) {
    throw "Unable to restore direct V0-I2/C1 source files."
}

if (-not $InventoryPlacementInstalled) {
    Write-Host "[V0-I2] Applying seven-days cursor placement fix..."
    Invoke-GitApply $InventoryPatch
}
if (-not $SessionPlumbingInstalled) {
    Write-Host "[V0-C1] Applying construction session plumbing..."
    Invoke-GitApply $SessionPatch
}
if (-not $BuildControlsInstalled) {
    Write-Host "[V0-C1] Applying inventory build controls..."
    Invoke-GitApply $ControlsPatch
}
if (-not $ConstructionFrameInstalled) {
    Write-Host "[V0-C2] Applying Earth observer-frame integration..."
    Invoke-GitApply $ObserverPatch
}

& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed after V0-I2/C1 sync."
}

$FinalMarkers = @(
    @{ Path = "scripts/ui/inventory/item_cell.gd"; Text = "7DTD click-carry is atomic on press"; Name = "inventory placement" },
    @{ Path = "scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd"; Text = 'snapshot_packet["client_session"]'; Name = "server construction session" },
    @{ Path = "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"; Text = "func get_construction_session()"; Name = "client construction session" },
    @{ Path = "scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd"; Text = "func build_next_stage_blocking()"; Name = "outpost client adapter" },
    @{ Path = "scripts/ui/inventory/networked/m5_networked_inventory_shell.gd"; Text = "MvpOutpostClientAdapter"; Name = "inventory build controls" },
    @{ Path = "scripts/app/earth_construction_presentation.gd"; Text = "MVP_OUTPOST_PLANAR_POSITION"; Name = "C22/C24 outpost projection" }
)
foreach ($Marker in $FinalMarkers) {
    Assert-Marker $Marker.Path $Marker.Text $Marker.Name
}

$FinalLegacyObserver = Test-Marker `
    "scripts/app/earth_app.gd" `
    "func _update_construction_observer_frame()"
$FinalEarthFixedAnchor = (
    (Test-Marker "scripts/app/earth_app.gd" "func _update_construction_render_transform()") -and
    (Test-Marker "scripts/app/earth_app.gd" "EarthSurfaceRenderProjectorScript.project_anchor") -and
    (Test-Marker "scripts/app/earth_construction_presentation.gd" "func set_derived_render_transform")
)
if (-not ($FinalLegacyObserver -or $FinalEarthFixedAnchor)) {
    throw "Required Construction Earth-frame projection is missing after sync."
}

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable not found for focused validation: $GodotExe"
}

Write-Host "[V0-I2/C1] Godot parser preflight..." -ForegroundColor Cyan
& $GodotExe --headless --path $ProjectRoot --editor --quit-after 1
if ($LASTEXITCODE -ne 0) {
    throw "Godot parser preflight failed."
}

$FocusedTests = @(
    "res://tests/runtime/test_v0_i2_inventory_click_place.gd",
    "res://tests/runtime/test_v0_c1_mvp_outpost_client_adapter.gd",
    "res://tests/runtime/test_mvp_earth_outpost_authority.gd",
    "res://tests/runtime/test_mvp_m3_construction_replication_bridge.gd",
    "res://tests/runtime/test_mvp_earth_c22_construction_presentation.gd"
)
foreach ($TestScript in $FocusedTests) {
    $LocalTestPath = Join-Path $ProjectRoot ($TestScript.Replace("res://", "").Replace("/", "\"))
    if (-not (Test-Path $LocalTestPath)) {
        throw "Focused test is missing: $TestScript"
    }
    Write-Host "[V0-I2/C1] Running $TestScript"
    & $GodotExe --headless --path $ProjectRoot --script $TestScript
    if ($LASTEXITCODE -ne 0) {
        throw "Focused test failed: $TestScript"
    }
}

$BranchRaw = & git branch --show-current
$Branch = "(detached HEAD)"
if ($null -ne $BranchRaw) {
    $CandidateBranch = ([string]$BranchRaw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($CandidateBranch)) {
        $Branch = $CandidateBranch
    }
}
$HeadRaw = & git rev-parse --short=12 HEAD
$Head = ([string]$HeadRaw).Trim()
Write-Host ""
Write-Host "[V0-I2/C1] PASS - inventory interaction and MVP outpost construction are installed." -ForegroundColor Green
Write-Host "  local branch : $Branch"
Write-Host "  local HEAD   : $Head"
Write-Host "  inventory    : world -> cursor -> empty inventory slot now commits on click"
Write-Host "  construction : canonical 3-stage outpost commands exposed in inventory"
Write-Host "  replication  : construction session + events remain server authoritative"
Write-Host "  presentation : canonical outpost bundle feeds C22/C24 mesh projection"
Write-Host "  earth frame  : $(if ($FinalEarthFixedAnchor) { 'C2A fixed Earth anchor' } else { 'legacy observer tangent frame' })"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Next: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
