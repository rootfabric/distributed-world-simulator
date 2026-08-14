[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$MainPayloadPath = Join-Path $PSScriptRoot "patches\v0-s0-stabilize-controls-network.patch.gz.b64"
$CameraPatchPath = Join-Path $PSScriptRoot "patches\v0-s0-camera-followup-post-hud.patch"
$ExpectedMainPatchSha256 = "aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f"
$ExpectedCameraPatchSha256 = "2a69db208b31910e3a52291af0a225789aee97c47789b73a3feb533c3d674088"
$CameraPath = "scripts/actors/earth/earth_explorer.gd"

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

if (-not (Test-Path (Join-Path $PSScriptRoot ".git"))) {
    throw "Run this script from the repository root: C:\distributed-world-simulator"
}
if (-not (Test-Path $MainPayloadPath)) {
    throw "Missing main stabilization payload: $MainPayloadPath"
}
if (-not (Test-Path $CameraPatchPath)) {
    throw "Missing post-HUD camera patch: $CameraPatchPath"
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

# Git may check out the text camera patch as CRLF on Windows. Normalize to LF
# before hashing so the integrity check is independent of core.autocrlf.
$CameraText = Get-Content -Path $CameraPatchPath -Raw
$NormalizedCameraText = $CameraText -replace "`r`n", "`n"
$CameraPatchBytes = [Text.Encoding]::UTF8.GetBytes($NormalizedCameraText)
$ActualCameraSha = Get-Sha256Hex $CameraPatchBytes
if ($ActualCameraSha -ne $ExpectedCameraPatchSha256) {
    throw "V0-S0 camera payload checksum mismatch: $ActualCameraSha"
}

$MainPatchPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v2-main.patch"
$NormalizedCameraPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network-v2-camera.patch"
[IO.File]::WriteAllBytes($MainPatchPath, $MainPatchBytes)
[IO.File]::WriteAllBytes($NormalizedCameraPath, $CameraPatchBytes)

try {
    Write-Host "[V0-S0/V2] Checking main stabilization against current convergence tree..."
    & git apply --check "--exclude=$CameraPath" -- $MainPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization does not match the current working tree. Nothing was changed."
    }

    Write-Host "[V0-S0/V2] Checking camera follow-up against the already installed HUD/horizon layer..."
    & git apply --check -- $NormalizedCameraPath
    if ($LASTEXITCODE -ne 0) {
        throw "Camera follow-up does not match the current earth_explorer.gd. Nothing was changed."
    }

    Write-Host "[V0-S0/V2] Applying main stabilization (camera file excluded)..."
    & git apply "--exclude=$CameraPath" -- $MainPatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Main stabilization apply failed."
    }

    Write-Host "[V0-S0/V2] Applying rebased camera stabilization..."
    & git apply -- $NormalizedCameraPath
    if ($LASTEXITCODE -ne 0) {
        throw "Camera stabilization apply failed."
    }

    & git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after V0-S0/V2 application."
    }
}
finally {
    Remove-Item $MainPatchPath -Force -ErrorAction SilentlyContinue
    Remove-Item $NormalizedCameraPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "[V0-S0/V2] PASS - stabilization applied over current local convergence state." -ForegroundColor Green
Write-Host "  camera    : scalar surface yaw/pitch, pitch clamp, roll-free rebuild"
Write-Host "  input     : explicit GAMEPLAY / INVENTORY / SPECTATOR ownership"
Write-Host "  movement  : NX4 predicted input path restored"
Write-Host "  stop      : explicit neutral input on ownership handoff"
Write-Host "  transport : ordered unreliable physical ENet mapping"
Write-Host "  HUD       : collapsed + F1 hide/show"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Next: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
