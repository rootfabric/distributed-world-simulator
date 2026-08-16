[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) {
    throw "Godot project.godot missing: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot 4.7.1 double console executable missing: $GodotExe"
}

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "P5 projection gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
}

function Test-UdpPortAvailable {
    param([int]$Port)
    $Udp = $null
    try {
        $Udp = [System.Net.Sockets.UdpClient]::new([System.Net.Sockets.AddressFamily]::InterNetwork)
        $Udp.Client.ExclusiveAddressUse = $true
        $Udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        return $true
    }
    catch { return $false }
    finally { if ($null -ne $Udp) { $Udp.Dispose() } }
}

foreach ($Port in @(25880, 25881)) {
    if (-not (Test-UdpPortAvailable $Port)) {
        throw "P5 focused projection gate requires free UDP loopback port $Port."
    }
}

$Scripts = @(
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_store.gd",
    "res://scripts/runtime/seamless/sm0/sm0_p5_projection_server_node.gd",
    "res://tests/runtime/seamless/sm0/test_sm0_p5_two_authority_projections.gd"
)

foreach ($ScriptPath in $Scripts) {
    Write-Host "[SM0-P5] Compile check: $ScriptPath"
    & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "P5 compile check failed: $ScriptPath"
    }
}

Write-Host "[SM0-P5] Running two-authority read-only projection regression..."
& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p5_two_authority_projections.gd
if ($LASTEXITCODE -ne 0) {
    throw "SM0 P5 two-authority projection regression failed."
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed after P5 gate" }
if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
    throw "P5 gate mutated the source worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
}

Write-Host ""
Write-Host "SM0-P5 two-authority read-only projections: PASS" -ForegroundColor Green
Write-Host "  HEAD       : $GitHead"
Write-Host "  canonical A: player/a on authority/sm0/a"
Write-Host "  canonical B: player/b on authority/sm0/b"
Write-Host "  projection : foreign player state only / read-only"
Write-Host "  mutation   : projection writes fail with SM0_P5_PROJECTION_READ_ONLY"
Write-Host "  P4 protocol: unchanged"