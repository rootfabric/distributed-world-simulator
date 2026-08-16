[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
$CanonicalWorkspaceRoot = "C:\distributed-world-simulator"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith($CanonicalWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0 Windows proof gate must run below $CanonicalWorkspaceRoot. Current project: $ProjectRoot"
}
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
    throw "P4 durable-proof gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
}

$HadBreakpoint = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
$PreviousBreakpoint = $env:BREAKPOINT_RUNTIME_DISABLED
$ExitCode = 1
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    foreach ($ScriptPath in @(
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd",
        "res://tests/runtime/seamless/sm0/sm0_p4_durable_proof_test_server.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd"
    )) {
        Write-Host "[SM0-P4] Compile check: $ScriptPath"
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) {
            throw "Compile check failed: $ScriptPath"
        }
    }

    Write-Host "[SM0-P4] Running durable PREWARM proof recovery regression..."
    & $GodotExe `
        --headless `
        --path $ProjectRoot `
        --script res://tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd
    if ($LASTEXITCODE -ne 0) {
        throw "SM0 P4 durable proof recovery regression failed."
    }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P4 durable-proof gate" }
    if (-not $AllowDirty -and (($StatusAfter -join "`n") -ne ($StatusBefore -join "`n"))) {
        throw "P4 durable-proof gate mutated the source worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")"
    }
    $ExitCode = 0
}
finally {
    if ($HadBreakpoint) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpoint }
    else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "SM0-P4 durable proof recovery gate: PASS" -ForegroundColor Green
    Write-Host "  HEAD  : $GitHead"
    Write-Host "  proof : survives live TTL / restart-memory loss"
    Write-Host "  fence : active target + checksum + directory drift fail closed"
    Write-Host "  replay: exact replay ACK / conflicting replay rejected"
}
else {
    Write-Host "SM0-P4 durable proof recovery gate: FAIL" -ForegroundColor Red
    Write-Host "  HEAD : $GitHead"
}
exit $ExitCode
