[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$DeliveryRef = "origin/agent/v0-s1-inventory-convergence"
$MainPayloadPath = Join-Path $PSScriptRoot "patches\v0-s0-stabilize-controls-network.patch.gz.b64"
$CameraPatchPath = Join-Path $PSScriptRoot "patches\v0-s0-camera-followup-post-hud.patch"
$OverlayPatchPath = Join-Path $PSScriptRoot "patches\v0-s0-overlay-followup-post-hud.patch"

$ExpectedMainPatchSha256 = "aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f"
$ExpectedCameraBlobSha = "1cd9efa484b2e37ad5aa1f7ada8156c00e912840"
$ExpectedOverlayBlobSha = "5350a0f13c58434d5fbb4371ff390a0d4cd76eaa"

$CameraPath = "scripts/actors/earth/earth_explorer.gd"
$OverlayPath = "scripts/ui/planetary_overlay.gd"
$CameraPatchRepoPath = "patches/v0-s0-camera-followup-post-hud.patch"
$OverlayPatchRepoPath = "patches/v0-s0-overlay-followup-post-hud.patch"

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

function Get-RemoteBlobSha {
    param([string]$RepoPath)
    $Spec = "${DeliveryRef}:$RepoPath"
    $Result = & git rev-parse $Spec
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve delivery object: $Spec. Run git fetch origin first."
    }
    return ([string]$Result).Trim().ToLowerInvariant()
}

if (-not (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    throw "Run this script from the repository root: C:\distributed-world-simulator"
}
foreach ($RequiredPath in @($MainPayloadPath, $CameraPatchPath, $OverlayPatchPath)) {
    if (-not (Test-Path $RequiredPath)) {
        throw "Missing V0-S0/V3 payload: $RequiredPath"
    }
}

Set-Location $PSScriptRoot

# The binary payload is base64 text. Whitespace/CRLF do not affect decoding,
# and the SHA is computed on the decompressed canonical patch bytes.
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

# Verify the canonical text-patch objects in the fetched delivery ref. We do
# NOT hash the Windows working-tree representation because core.autocrlf and
# PowerShell 5.1 encoding can legitimately change its byte representation.
$RemoteCameraBlobSha = Get-RemoteBlobSha $CameraPatchRepoPath
if ($RemoteCameraBlobSha -ne $ExpectedCameraBlobSha) {
    throw "V0-S0 remote camera payload mismatch: $RemoteCameraBlobSha"
}
$RemoteOverlayBlobSha = Get-RemoteBlobSha $OverlayPatchRepoPath
if ($RemoteOverlayBlobSha -ne $ExpectedOverlayBlobSha) {
    throw "V0-S0 remote overlay payload mismatch: $RemoteOverlayBlobSha"
}

$CameraSource = Get-Content -Path (Join-Path $PSScriptRoot $CameraPath) -Raw
$OverlaySource = Get-Content -Path (Join-Path $PSScriptRoot $OverlayPath) -Raw
$CameraHasPriorHudLayer = $CameraSource.Contains("func _apply_surface_locked_mouse_look")
$OverlayHasPriorHudLayer = $OverlaySource.Contains("var minimize_button: Button")

if ($CameraSource.Contains("var _network_surface_view_initialized: bool = false")) {
    throw "V0-S0/V3 camera stabilization already appears to be applied. Refusing duplicate apply."
}
if ($OverlaySource.Contains("var _content: VBoxContainer") -and $OverlaySource.Contains("var _minimized: bool = true")) {
    throw "V0-S0/V3 overlay stabilization already appears to be applied. Refusing duplicate apply."
}

$MainPatchPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v3-main.patch"
[IO.File]::WriteAllBytes($MainPatchPath, $MainPatchBytes)

$ExcludeArgs = @()
if ($CameraHasPriorHudLayer) {
    $ExcludeArgs += "--exclude=$CameraPath"
}
if ($OverlayHasPriorHudLayer) {
    $ExcludeArgs += "--exclude=$OverlayPath"
}

try {
    Write-Host "[V0-S0/V3] Current local layers:" -ForegroundColor Cyan
    Write-Host "  camera prior HUD layer : $CameraHasPriorHudLayer"
    Write-Host "  overlay prior HUD layer: $OverlayHasPriorHudLayer"
    Write-Host "  remote camera blob     : $RemoteCameraBlobSha"
    Write-Host "  remote overlay blob    : $RemoteOverlayBlobSha"

    Write-Host "[V0-S0/V3] Checking main stabilization..."
    $MainCheckArgs = @("apply", "--check") + $ExcludeArgs + @("--", $MainPatchPath)
    & git @MainCheckArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization does not match the current working tree. Nothing was changed."
    }

    if ($CameraHasPriorHudLayer) {
        Write-Host "[V0-S0/V3] Checking rebased camera follow-up..."
        & git apply --check -- $CameraPatchPath
        if ($LASTEXITCODE -ne 0) {
            throw "Camera follow-up does not match current earth_explorer.gd. Nothing was changed."
        }
    }

    if ($OverlayHasPriorHudLayer) {
        Write-Host "[V0-S0/V3] Checking rebased overlay follow-up..."
        & git apply --check -- $OverlayPatchPath
        if ($LASTEXITCODE -ne 0) {
            throw "Overlay follow-up does not match current planetary_overlay.gd. Nothing was changed."
        }
    }

    Write-Host "[V0-S0/V3] All checks passed. Applying main stabilization..."
    $MainApplyArgs = @("apply") + $ExcludeArgs + @("--", $MainPatchPath)
    & git @MainApplyArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization apply failed."
    }

    if ($CameraHasPriorHudLayer) {
        Write-Host "[V0-S0/V3] Applying rebased camera stabilization..."
        & git apply -- $CameraPatchPath
        if ($LASTEXITCODE -ne 0) {
            throw "Camera stabilization apply failed."
        }
    }

    if ($OverlayHasPriorHudLayer) {
        Write-Host "[V0-S0/V3] Applying rebased overlay stabilization..."
        & git apply -- $OverlayPatchPath
        if ($LASTEXITCODE -ne 0) {
            throw "Overlay stabilization apply failed."
        }
    }

    & git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after V0-S0/V3 application."
    }
}
finally {
    Remove-Item $MainPatchPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "[V0-S0/V3] PASS - stabilization applied over the actual local convergence tree." -ForegroundColor Green
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
