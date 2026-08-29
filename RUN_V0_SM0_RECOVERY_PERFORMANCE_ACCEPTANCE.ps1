[CmdletBinding()]
param(
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not $ProjectRoot.StartsWith("C:\distributed-world-simulator", [StringComparison]::OrdinalIgnoreCase)) {
    throw "SM0-P2.1 must run under C:\distributed-world-simulator. Current: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw "Godot double console executable not found: $GodotExe"
}

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0-P2.1 requires a clean worktree:`n$($StatusBefore -join "`n")"
}
$Head = (& git -C $ProjectRoot rev-parse HEAD).Trim()
$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) { $UidBeforeSet[[string]$RelativeUid] = $true }

$ExpectedVersion = "4.7.1.stable.double.custom_build.a13da4feb"
$VersionText = (& $GodotExe --version | Select-Object -First 1).Trim()
if ($VersionText -ne $ExpectedVersion) { throw "Unexpected Godot version: $VersionText" }

function Invoke-P21Godot([string[]]$Arguments) {
    $HadDisabled = Test-Path Env:BREAKPOINT_RUNTIME_DISABLED
    $PreviousDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
    try {
        $env:BREAKPOINT_RUNTIME_DISABLED = "1"
        # Native stdout is data in the PowerShell success pipeline. If we invoke
        # Godot directly and then `return $LASTEXITCODE`, callers receive both
        # the banner/output and the numeric exit code. That makes a successful
        # `0` compare as a non-zero composite value. Capture and replay output
        # to the host so the function's only pipeline result is the integer exit.
        $Output = @(& $GodotExe @Arguments 2>&1)
        $Exit = [int]$LASTEXITCODE
        foreach ($Line in $Output) { Write-Host $Line }
        return $Exit
    }
    finally {
        if ($HadDisabled) { $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousDisabled }
        else { Remove-Item Env:BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    }
}

$ExitCode = 1
try {
    Write-Host "[SM0-P2.1] HEAD=$Head"
    foreach ($ScriptPath in @(
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd",
        "res://scripts/runtime/seamless/sm0/sm0_authority_server_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_recovery_performance.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd"
    )) {
        Write-Host "[SM0-P2.1] Compile check: $ScriptPath"
        $CompileExit = Invoke-P21Godot @("--headless", "--path", $ProjectRoot, "--check-only", "--script", $ScriptPath)
        if ($CompileExit -ne 0) { throw "compile check failed: $ScriptPath (exit $CompileExit)" }
    }

    Write-Host "[SM0-P2.1] Running established active-owner recovery regression..."
    $ActiveExit = Invoke-P21Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/seamless/sm0/test_sm0_active_owner_recovery.gd")
    if ($ActiveExit -ne 0) { throw "active-owner recovery regression failed (exit $ActiveExit)" }

    Write-Host "[SM0-P2.1] Running bounded movement recovery regression..."
    $PerfExit = Invoke-P21Godot @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/seamless/sm0/test_sm0_recovery_performance.gd")
    if ($PerfExit -ne 0) { throw "P2.1 bounded recovery regression failed (exit $PerfExit)" }

    Write-Host ""
    Write-Host "SM0-P2.1 bounded recovery performance: PASS" -ForegroundColor Green
    Write-Host "  HEAD  : $Head"
    Write-Host "  Godot : $VersionText"
    $ExitCode = 0
}
catch {
    Write-Error "SM0-P2.1 FAIL: $($_.Exception.Message)" -ErrorAction Continue
    $ExitCode = 1
}
finally {
    $UidAfter = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
    if ($LASTEXITCODE -eq 0) {
        foreach ($RelativeUid in $UidAfter) {
            $RelativeUidText = [string]$RelativeUid
            if (-not $UidBeforeSet.ContainsKey($RelativeUidText)) {
                $GeneratedPath = Join-Path $ProjectRoot $RelativeUidText
                if (Test-Path -LiteralPath $GeneratedPath -PathType Leaf) {
                    Remove-Item -LiteralPath $GeneratedPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if (($StatusBefore -join "`n") -ne ($StatusAfter -join "`n")) {
    Write-Error "SM0-P2.1 mutated worktree. Before:`n$($StatusBefore -join "`n")`nAfter:`n$($StatusAfter -join "`n")" -ErrorAction Continue
    exit 1
}
exit $ExitCode
