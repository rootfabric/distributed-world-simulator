[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$MainPayloadPath = Join-Path $PSScriptRoot "patches\v0-s0-stabilize-controls-network.patch.gz.b64"
$CameraPatchPath = Join-Path $PSScriptRoot "patches\v0-s0-camera-followup-post-hud.patch"
$OverlayPatchPath = Join-Path $PSScriptRoot "patches\v0-s0-overlay-followup-post-hud.patch"
$ExpectedMainPatchSha256 = "aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f"
$ExpectedCameraPatchSha256 = "2a69db208b31910e3a52291af0a225789aee97c47789b73a3feb533c3d674088"
$ExpectedOverlayPatchSha256 = "5d53b36d86d024fdb011ac554fd3c76f96823de38937327b588e680e868bb460"
$CameraPath = "scripts/actors/earth/earth_explorer.gd"
$OverlayPath = "scripts/ui/planetary_overlay.gd"

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-NormalizedTextBytes {
    param([string]$Path)
    $Text = Get-Content -Path $Path -Raw
    $Normalized = $Text -replace "`r`n", "`n"
    return [Text.Encoding]::UTF8.GetBytes($Normalized)
}

if (-not (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    throw "Run this script from the repository root: C:\distributed-world-simulator"
}
foreach ($RequiredPath in @($MainPayloadPath, $CameraPatchPath, $OverlayPatchPath)) {
    if (-not (Test-Path $RequiredPath)) {
        throw "Missing V0-S0/V2 payload: $RequiredPath"
    }
}

Set-Location $PSScriptRoot

$Encoded = Get-Content -Path $MainPayloadPath -Raw
$CompressedBytes = [Convert]::FromBase64String(($Encoded -replace "\s", ""))
$InputStream = New-Object System.IO.MemoryStream(,$CompressedBytes)
$GzipStream = New-Object System.IO.Compression.GZipStream($InputStream, [System.IO.Compression.CompressionMode]::Decompress)
$OutputStream = New-Object System.IO.MemoryStream
try {
    $GzipStream.CopyTo($OutputStream)
    $MainPatchBytes = $OutputStream.ToArray()
}
finally {
    $GzipStream.Dispose()
    $InputStream.Dispose()
    $OutputStream.Dispose()
}

$ActualMainSha = Get-Sha256Hex $MainPatchBytes
if ($ActualMainSha -ne $ExpectedMainPatchSha256) {
    throw "V0-S0 main payload checksum mismatch: $ActualMainSha"
}

$CameraPatchBytes = Get-NormalizedTextBytes $CameraPatchPath
$ActualCameraSha = Get-Sha256Hex $CameraPatchBytes
if ($ActualCameraSha -ne $ExpectedCameraPatchSha256) {
    throw "V0-S0 camera payload checksum mismatch: $ActualCameraSha"
}

$OverlayPatchBytes = Get-NormalizedTextBytes $OverlayPatchPath
$ActualOverlaySha = Get-Sha256Hex $OverlayPatchBytes
if ($ActualOverlaySha -ne $ExpectedOverlayPatchSha256) {
    throw "V0-S0 overlay payload checksum mismatch: $ActualOverlaySha"
}

$CameraSource = Get-Content -Path (Join-Path $PSScriptRoot $CameraPath) -Raw
$OverlaySource = Get-Content -Path (Join-Path $PSScriptRoot $OverlayPath) -Raw
$CameraHasPriorHudLayer = $CameraSource.Contains("func _apply_surface_locked_mouse_look")
$OverlayHasPriorHudLayer = $OverlaySource.Contains("var minimize_button: Button")

if ($CameraSource.Contains("var _network_surface_view_initialized: bool = false")) {
    throw "V0-S0/V2 camera stabilization already appears to be applied. Refusing a duplicate apply."
}
if ($OverlaySource.Contains("var _content: VBoxContainer") -and $OverlaySource.Contains("var _minimized: bool = true")) {
    throw "V0-S0/V2 overlay stabilization already appears to be applied. Refusing a duplicate apply."
}

$MainPatchPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v2-main.patch"
$NormalizedCameraPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v2-camera.patch"
$NormalizedOverlayPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v2-overlay.patch"
[IO.File]::WriteAllBytes($MainPatchPath, $MainPatchBytes)
[IO.File]::WriteAllBytes($NormalizedCameraPath, $CameraPatchBytes)
[IO.File]::WriteAllBytes($NormalizedOverlayPath, $OverlayPatchBytes)

$ExcludeArgs = @()
if ($CameraHasPriorHudLayer) {
    $ExcludeArgs += "--exclude=$CameraPath"
}
if ($OverlayHasPriorHudLayer) {
    $ExcludeArgs += "--exclude=$OverlayPath"
}

try {
    Write-Host "[V0-S0/V2] Current local layers:" -ForegroundColor Cyan
    Write-Host "  camera prior HUD layer : $CameraHasPriorHudLayer"
    Write-Host "  overlay prior HUD layer: $OverlayHasPriorHudLayer"

    Write-Host "[V0-S0/V2] Checking main stabilization..."
    $MainCheckArgs = @("apply", "--check") + $ExcludeArgs + @("--", $MainPatchPath)
    & git @MainCheckArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization does not match the current working tree. Nothing was changed."
    }

    if ($CameraHasPriorHudLayer) {
        Write-Host "[V0-S0/V2] Checking rebased camera follow-up..."
        & git apply --check -- $NormalizedCameraPath
        if ($LASTEXITCODE -ne 0) {
            throw "Camera follow-up does not match current earth_explorer.gd. Nothing was changed."
        }
    }

    if ($OverlayHasPriorHudLayer) {
        Write-Host "[V0-S0/V2] Checking rebased overlay follow-up..."
        & git apply --check -- $NormalizedOverlayPath
        if ($LASTEXITCODE -ne 0) {
            throw "Overlay follow-up does not match current planetary_overlay.gd. Nothing was changed."
        }
    }

    Write-Host "[V0-S0/V2] All checks passed. Applying main stabilization..."
    $MainApplyArgs = @("apply") + $ExcludeArgs + @("--", $MainPatchPath)
    & git @MainApplyArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization apply failed."
    }

    if ($CameraHasPriorHudLayer) {
        Write-Host "[V0-S0/V2] Applying rebased camera stabilization..."
        & git apply -- $NormalizedCameraPath
        if ($LASTEXITCODE -ne 0) {
            throw "Camera stabilization apply failed."
        }
    }

    if ($OverlayHasPriorHudLayer) {
        Write-Host "[V0-S0/V2] Applying rebased overlay stabilization..."
        & git apply -- $NormalizedOverlayPath
        if ($LASTEXITCODE -ne 0) {
            throw "Overlay stabilization apply failed."
        }
    }

    & git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after V0-S0/V2 application."
    }
}
finally {
    Remove-Item $MainPatchPath -Force -ErrorAction SilentlyContinue
    Remove-Item $NormalizedCameraPath -Force -ErrorAction SilentlyContinue
    Remove-Item $NormalizedOverlayPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "[V0-S0/V2] PASS - stabilization applied over the actual local convergence tree." -ForegroundColor Green
Write-Host "  camera    : scalar surface yaw/pitch, pitch clamp, roll-free rebuild"
Write-Host "  input     : explicit GAMEPLAY / INVENTORY / SPECTATOR ownership"
Write-Host "  movement  : NX4 predicted input path restored"
Write-Host "  stop      : explicit neutral input on ownership handoff"
Write-Host "  transport : ordered unreliable physical ENet mapping"
Write-Host "  HUD       : starts collapsed + F1 hide/show"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Next: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
