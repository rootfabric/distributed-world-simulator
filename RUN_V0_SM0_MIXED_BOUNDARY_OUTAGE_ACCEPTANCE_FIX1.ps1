[CmdletBinding()]
param(
    [ValidateRange(3, 12)][int]$Handoffs = 3,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(60, 900)][int]$TimeoutSeconds = 360
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_MIXED_BOUNDARY_OUTAGE_ACCEPTANCE.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) {
    throw "SM0-H4.2 source runner not found: $SourceRunner"
}

# H4.2 FIX1 is harness-only. The original runner waited for any event carrying
# the boundary field. During INFLIGHT_RETIRE the send-suppression event is
# emitted before the crash-point event, so the runner could read the log in
# that small interval and falsely report CrashEvents.Count == 0.
#
# Patch only the temporary runner: wait for the exact crash-point event. The
# subsequent strict boundary/epoch/transfer assertions remain unchanged.
$Original = Get-Content -LiteralPath $SourceRunner -Raw -ErrorAction Stop
$Needle = '        Wait-H42Marker $CrashLog (''"boundary":"'' + $Boundary + ''"'') $CrashProcess 50'
$Replacement = '        Wait-H42Marker $CrashLog ''"event":"SM0_H4_MIXED_CRASH_POINT"'' $CrashProcess 50'
$Matches = ([regex]::Matches($Original, [regex]::Escape($Needle))).Count
if ($Matches -ne 1) {
    throw "SM0-H4.2 FIX1 expected exactly one broad boundary wait to replace, found $Matches."
}
$Patched = $Original.Replace($Needle, $Replacement)
if ($Patched -eq $Original) {
    throw "SM0-H4.2 FIX1 replacement produced no change."
}
if (([regex]::Matches($Patched, [regex]::Escape($Needle))).Count -ne 0) {
    throw "SM0-H4.2 FIX1 left the broad boundary wait in the patched runner."
}
if (([regex]::Matches($Patched, [regex]::Escape($Replacement))).Count -ne 1) {
    throw "SM0-H4.2 FIX1 did not produce exactly one exact crash-point wait."
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "distributed-world-simulator-sm0-h42-fix1"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$TempRunner = Join-Path $TempRoot ("RUN_V0_SM0_MIXED_BOUNDARY_OUTAGE_ACCEPTANCE_FIX1_{0}_{1}.ps1" -f $PID, ([Guid]::NewGuid().ToString("N")))
$Patched | Set-Content -LiteralPath $TempRunner -Encoding UTF8

$Invoke = @{
    Handoffs = $Handoffs
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = $TimeoutSeconds
}
if ($Final) { $Invoke.Final = $true }
if ($Stop) { $Invoke.Stop = $true }
if ($Restart) { $Invoke.Restart = $true }
if ($AllowDirty) { $Invoke.AllowDirty = $true }

try {
    Write-Host "[SM0-H4.2-FIX1] Applying exact crash-point wait to temporary runner only."
    & $TempRunner @Invoke
    $Code = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $TempRunner -Force -ErrorAction SilentlyContinue
}

exit $Code
