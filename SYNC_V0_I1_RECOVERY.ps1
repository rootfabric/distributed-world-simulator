[CmdletBinding()]
param(
    [string]$DeliveryBranch = "agent/v0-s1-inventory-convergence"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $Root

$ExpectedCumulativeSha256 = "090ace9b6a9e644a4a1956980a80becb03186e1f1edb0b27250e452f3ebab6b8"
$EarthMvp = Join-Path $Root "scripts/app/earth_mvp_app.gd"
$InventoryShell = Join-Path $Root "scripts/ui/inventory/networked/m5_networked_inventory_shell.gd"

function Invoke-Git([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Test-TextMarker([string]$Path, [string]$Marker) {
    if (-not (Test-Path $Path)) { return $false }
    return [bool](Select-String -LiteralPath $Path -SimpleMatch -Quiet -Pattern $Marker)
}

function Export-GitPath([string]$Spec, [string]$Destination) {
    $Command = 'git show "{0}" > "{1}"' -f $Spec, $Destination
    & cmd.exe /d /s /c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to export $Spec"
    }
}

function Apply-PatchFile([string]$PatchPath, [string]$Label) {
    & git apply --check -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "$Label does not apply to the current recovery working tree. Stop here; no later recovery layer was applied."
    }
    & git apply -- $PatchPath
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed during git apply."
    }
}

try {
    if (-not (Test-Path $EarthMvp)) {
        throw "Earth MVP adapter is missing: $EarthMvp"
    }

    Write-Host "[V0-I1] Fetching historical delivery ref..." -ForegroundColor Cyan
    Invoke-Git @("fetch", "origin", $DeliveryBranch)
    $DeliveryRef = "origin/$DeliveryBranch"

    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("v0-i1-recovery-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempDir | Out-Null
    try {
        $HasInventory = Test-TextMarker $EarthMvp "_mvp_inventory_shell"
        if (-not $HasInventory) {
            Write-Host "[V0-I1 1/3] Restoring cumulative MVP + inventory convergence..." -ForegroundColor Cyan
            $GzPath = Join-Path $TempDir "v0-s1-inventory-convergence-cumulative.patch.gz"
            $PatchPath = Join-Path $TempDir "v0-s1-inventory-convergence-cumulative.patch"
            Export-GitPath "$DeliveryRef`:patches/v0-s1-inventory-convergence-cumulative.patch.gz" $GzPath

            $InputStream = [System.IO.File]::OpenRead($GzPath)
            try {
                $Gzip = New-Object System.IO.Compression.GZipStream($InputStream, [System.IO.Compression.CompressionMode]::Decompress)
                try {
                    $OutputStream = [System.IO.File]::Create($PatchPath)
                    try { $Gzip.CopyTo($OutputStream) } finally { $OutputStream.Dispose() }
                } finally { $Gzip.Dispose() }
            } finally { $InputStream.Dispose() }

            $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash.ToLowerInvariant()
            if ($ActualHash -ne $ExpectedCumulativeSha256) {
                throw "Historical cumulative I1 patch hash mismatch. Expected $ExpectedCumulativeSha256, got $ActualHash."
            }
            Apply-PatchFile $PatchPath "Historical cumulative I1 patch"
        } else {
            Write-Host "[V0-I1 1/3] Inventory convergence already present; reusing it." -ForegroundColor DarkGray
        }

        $HasMovement = (
            (Test-TextMarker $EarthMvp "V0-NET-001") -and
            (Test-TextMarker $EarthMvp "move_nonblocking")
        )
        if (-not $HasMovement) {
            Write-Host "[V0-I1 2/3] Restoring reliable camera-relative movement fallback..." -ForegroundColor Cyan
            $MovementPatch = Join-Path $TempDir "v0-i1-movement-reliable-camera-relative.patch"
            Export-GitPath "$DeliveryRef`:patches/v0-i1-movement-reliable-camera-relative.patch" $MovementPatch
            Apply-PatchFile $MovementPatch "Historical V0-I1 movement recovery patch"
        } else {
            Write-Host "[V0-I1 2/3] Movement recovery already present; reusing it." -ForegroundColor DarkGray
        }

        $HasMouseCapture = (
            (Test-TextMarker $InventoryShell "root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE") -and
            (Test-TextMarker $InventoryShell "inventory_window.mouse_filter = Control.MOUSE_FILTER_STOP")
        )
        if (-not $HasMouseCapture) {
            Write-Host "[V0-I1 3/3] Restoring gameplay mouse-capture fix..." -ForegroundColor Cyan
            $MousePatch = Join-Path $TempDir "v0-i1-fix-gameplay-mouse-capture.patch"
            Export-GitPath "$DeliveryRef`:patches/v0-i1-fix-gameplay-mouse-capture.patch" $MousePatch
            Apply-PatchFile $MousePatch "Historical V0-I1 mouse-capture patch"
        } else {
            Write-Host "[V0-I1 3/3] Mouse-capture fix already present; reusing it." -ForegroundColor DarkGray
        }

        & git diff --check
        if ($LASTEXITCODE -ne 0) {
            throw "git diff --check failed after V0-I1 recovery."
        }

        foreach ($Check in @(
            @{ Path = $EarthMvp; Marker = "_mvp_inventory_shell"; Name = "inventory convergence" },
            @{ Path = $EarthMvp; Marker = "move_nonblocking"; Name = "reliable movement recovery" },
            @{ Path = $InventoryShell; Marker = "root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE"; Name = "mouse-capture recovery" }
        )) {
            if (-not (Test-TextMarker $Check.Path $Check.Marker)) {
                throw "V0-I1 recovery marker missing after apply: $($Check.Name)"
            }
        }

        Write-Host "[V0-I1] Historical prerequisite stack is present." -ForegroundColor Green
    } finally {
        if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
    }
} finally {
    Pop-Location
}
