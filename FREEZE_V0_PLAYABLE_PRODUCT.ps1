[CmdletBinding()]
param(
    [string]$MaterializedBranch = "checkpoint/v0-playable-materialized-2026-08-15"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path (Join-Path $Root ".git"))) {
    $Root = (Get-Location).Path
}
Set-Location $Root

$ValidatedRecoveryHead = "70e68be743922d464db1e8bf51215802362a32f0"
$FrontierRef = "origin/feature/v0-playable-product-frontier"

function Test-Marker {
    param([string]$RelativePath, [string]$Text)
    $Path = Join-Path $Root $RelativePath
    if (-not (Test-Path $Path)) { return $false }
    return [bool](Select-String -LiteralPath $Path -SimpleMatch -Quiet -Pattern $Text)
}

function Assert-Marker {
    param([string]$RelativePath, [string]$Text, [string]$Name)
    if (-not (Test-Marker $RelativePath $Text)) {
        throw "Required playable marker missing: $Name [$RelativePath]"
    }
}

function Test-ValidGodotUidSidecar {
    param(
        [string]$RelativeUidPath,
        [hashtable]$AllowedSourcePaths
    )
    if (-not $RelativeUidPath.EndsWith(".gd.uid", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $SourcePath = $RelativeUidPath.Substring(0, $RelativeUidPath.Length - 4)
    $FullSourcePath = Join-Path $Root $SourcePath
    $FullUidPath = Join-Path $Root $RelativeUidPath
    if (-not (Test-Path $FullSourcePath) -or -not (Test-Path $FullUidPath)) {
        return $false
    }

    & git ls-files --error-unmatch -- $SourcePath 2>$null | Out-Null
    $SourceTracked = ($LASTEXITCODE -eq 0)
    $SourceAllowed = $AllowedSourcePaths.ContainsKey($SourcePath.Replace("\", "/"))
    if (-not ($SourceTracked -or $SourceAllowed)) {
        return $false
    }

    $UidText = (Get-Content -LiteralPath $FullUidPath -Raw).Trim()
    return [bool]($UidText -match '^uid://[a-z0-9]+$')
}

$Head = (& git rev-parse HEAD).Trim()
if ($Head -ne $ValidatedRecoveryHead) {
    throw "Freeze must start from the user-validated recovery source $ValidatedRecoveryHead; current HEAD is $Head. Do not freeze an unknown composition."
}

Write-Host "[FREEZE 1/5] Validating recovered playable composition..." -ForegroundColor Cyan
Assert-Marker "scripts/app/earth_mvp_app.gd" "_mvp_inventory_shell" "M5 inventory convergence"
Assert-Marker "scripts/app/earth_mvp_app.gd" "_mvp_input_owner" "explicit input ownership"
Assert-Marker "scripts/app/earth_mvp_app.gd" "advance_local_prediction" "NX4 local prediction"
Assert-Marker "scripts/app/earth_mvp_app.gd" '"look_yaw": earth_explorer.get_surface_relative_yaw()' "surface-relative movement yaw"
Assert-Marker "scripts/actors/earth/earth_explorer.gd" "_network_surface_view_initialized" "surface-locked network camera"
Assert-Marker "scripts/ui/planetary_overlay.gd" "_overlay_visible: bool = false" "F1 HUD hidden by default"
Assert-Marker "scripts/network/transports/v2/enet_multi_peer_transport_port.gd" "TRANSFER_MODE_UNRELIABLE_ORDERED" "ordered ENet realtime"
Assert-Marker "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd" "disconnected_this_poll" "disconnect guard"
Assert-Marker "scripts/ui/inventory/networked/m5_networked_inventory_shell.gd" "MvpOutpostClientAdapter" "inventory Construction controls"
Assert-Marker "scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd" "func build_next_stage_blocking()" "Construction client adapter"
Assert-Marker "scripts/app/earth_app.gd" "EarthSurfaceRenderProjectorScript.project_anchor" "C2A Earth-fixed Construction anchor"
Assert-Marker "scripts/app/earth_construction_presentation.gd" "func set_derived_render_transform" "derived Construction presentation"
Assert-Marker "scripts/world/earth/earth_asset_library.gd" "earth_surface_presentation.gdshader" "procedural Earth surface presentation"

if (Test-Marker "scripts/app/earth_mvp_app.gd" "V0-NET-001") {
    throw "Obsolete V0-NET-001 reliable MOVE fallback is present. This is NOT the validated playable baseline."
}

& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed; refusing to freeze."
}

$AllowedPaths = @(
    "RUN_V0_MVP.ps1",
    "scripts/actors/earth/earth_explorer.gd",
    "scripts/ui/planetary_overlay.gd",
    "scripts/network/realtime/realtime_channel_policy.gd",
    "scripts/network/transports/v2/enet_multi_peer_transport_port.gd",
    "scripts/app/earth_mvp_app.gd",
    "scripts/app/simulator_app.gd",
    "scripts/runtime/networked_gameplay/networked_gameplay_service.gd",
    "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd",
    "scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd",
    "scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd",
    "scripts/ui/inventory/networked/m5_networked_inventory_shell.gd",
    "scripts/ui/inventory/item_cell.gd",
    "scripts/app/earth_construction_presentation.gd",
    "tests/runtime/test_v0_i2_inventory_click_place.gd",
    "tests/runtime/test_v0_c1_mvp_outpost_client_adapter.gd"
)
$Allowed = @{}
foreach ($Path in $AllowedPaths) { $Allowed[$Path.Replace("\", "/")] = $true }

$Changed = @()
$UidSidecars = @()
foreach ($Line in (& git status --porcelain=v1 --untracked-files=all)) {
    if ([string]::IsNullOrWhiteSpace($Line)) { continue }
    $Path = $Line.Substring(3).Trim().Replace("\", "/")
    if ($Path.Contains(" -> ")) { $Path = $Path.Split(" -> ")[-1].Trim() }

    $AllowedChange = $Allowed.ContainsKey($Path)
    if (-not $AllowedChange -and (Test-ValidGodotUidSidecar $Path $Allowed)) {
        $AllowedChange = $true
        $UidSidecars += $Path
    }
    if (-not $AllowedChange) {
        throw "Unexpected local change outside the recovered playable allowlist: $Path. Refusing to freeze."
    }
    $Changed += $Path
}
$Changed = @($Changed | Sort-Object -Unique)
$UidSidecars = @($UidSidecars | Sort-Object -Unique)
if ($Changed.Count -eq 0) {
    throw "No materialized recovery changes are present. Run and validate RUN_V0_RECOVERED_PLAYABLE.ps1 before freezing."
}
if ($UidSidecars.Count -gt 0) {
    Write-Host ("[FREEZE] Including {0} validated Godot UID sidecar(s) generated by editor import." -f $UidSidecars.Count) -ForegroundColor DarkGray
}

Write-Host "[FREEZE 2/5] Fetching durable product frontier..." -ForegroundColor Cyan
& git fetch origin feature/v0-playable-product-frontier
if ($LASTEXITCODE -ne 0) { throw "Unable to fetch product frontier." }

$ExistingLocal = (& git branch --list $MaterializedBranch)
if (-not [string]::IsNullOrWhiteSpace(($ExistingLocal -join ""))) {
    throw "Local branch already exists: $MaterializedBranch. Refusing to reuse an ambiguous checkpoint name."
}

Write-Host "[FREEZE 3/5] Creating materialized checkpoint branch..." -ForegroundColor Cyan
& git switch -c $MaterializedBranch $FrontierRef
if ($LASTEXITCODE -ne 0) {
    throw "Unable to switch to $MaterializedBranch from $FrontierRef while preserving the validated working tree."
}

foreach ($Path in $Changed) {
    & git add -- $Path
    if ($LASTEXITCODE -ne 0) { throw "Unable to stage recovered source: $Path" }
}

$Staged = (& git diff --cached --name-only)
if ([string]::IsNullOrWhiteSpace(($Staged -join ""))) {
    throw "No recovered production changes were staged."
}

Write-Host "[FREEZE 4/5] Committing exact materialized playable source..." -ForegroundColor Cyan
& git commit -m "checkpoint(v0): materialize user-validated playable recovery"
if ($LASTEXITCODE -ne 0) { throw "Materialized playable commit failed." }
$MaterializedHead = (& git rev-parse HEAD).Trim()

Write-Host "[FREEZE 5/5] Publishing checkpoint and advancing product frontier..." -ForegroundColor Cyan
& git push -u origin $MaterializedBranch
if ($LASTEXITCODE -ne 0) { throw "Unable to push materialized checkpoint branch." }
& git push origin "HEAD:feature/v0-playable-product-frontier"
if ($LASTEXITCODE -ne 0) {
    throw "Materialized checkpoint was pushed, but product frontier did not fast-forward. Do not force-push; inspect the remote frontier."
}

Write-Host ""
Write-Host "V0 PLAYABLE MATERIALIZED CHECKPOINT PUBLISHED" -ForegroundColor Green
Write-Host "  checkpoint : $MaterializedBranch"
Write-Host "  HEAD       : $MaterializedHead"
Write-Host "  frontier   : feature/v0-playable-product-frontier"
Write-Host ""
Write-Host "Do not develop on the checkpoint branch. Continue from the product frontier."
