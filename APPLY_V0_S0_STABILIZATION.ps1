[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PayloadPath = Join-Path $PSScriptRoot "patches\v0-s0-stabilize-controls-network.patch.gz.b64"
$ExpectedPatchSha256 = "aa7e6160e91982d6f85015037dd98dd5f1de7b18b1f59d6a517493f688087c7f"

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
if (-not (Test-Path $PayloadPath)) {
    throw "Missing stabilization payload: $PayloadPath"
}

Set-Location $PSScriptRoot

$Encoded = Get-Content -Path $PayloadPath -Raw
$CompressedBytes = [Convert]::FromBase64String(($Encoded -replace "\s", ""))
$InputStream = New-Object System.IO.MemoryStream(,$CompressedBytes)
$GzipStream = New-Object System.IO.Compression.GZipStream($InputStream, [System.IO.Compression.CompressionMode]::Decompress)
$OutputStream = New-Object System.IO.MemoryStream
try {
    $GzipStream.CopyTo($OutputStream)
    $PatchBytes = $OutputStream.ToArray()
}
finally {
    $GzipStream.Dispose()
    $InputStream.Dispose()
    $OutputStream.Dispose()
}

$ActualSha = Get-Sha256Hex $PatchBytes
if ($ActualSha -ne $ExpectedPatchSha256) {
    throw "V0-S0 payload checksum mismatch: $ActualSha"
}

$PatchPath = Join-Path $env:TEMP "v0-s0-stabilize-controls-network.patch"
[IO.File]::WriteAllBytes($PatchPath, $PatchBytes)

try {
    Write-Host "[V0-S0] Checking patch against the current local convergence tree..."
    & git apply --check -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "Patch does not match the current working tree. Nothing was changed."
    }

    Write-Host "[V0-S0] Applying stabilization..."
    & git apply -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "git apply failed."
    }

    & git diff --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --check failed after application."
    }
}
finally {
    Remove-Item $PatchPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "[V0-S0] PASS - stabilization applied." -ForegroundColor Green
Write-Host "  camera    : surface-locked yaw/pitch, no accumulated roll"
Write-Host "  input     : GAMEPLAY / INVENTORY / SPECTATOR ownership"
Write-Host "  movement  : NX4 prediction restored; reliable MOVE fallback removed"
Write-Host "  transport : physical ENet UNRELIABLE_ORDERED + app sequencing"
Write-Host "  stop      : explicit zero intent when gameplay loses ownership"
Write-Host "  HUD       : starts collapsed; F1 hide/show"
Write-Host "  lifecycle : no false connect-timeout after real disconnect"
Write-Host ""
& git diff --stat
Write-Host ""
Write-Host "Run: .\RUN_V0_MVP.ps1 -Clients 2 -Restart"
