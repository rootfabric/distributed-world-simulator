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

# H4.2 FIX2 is harness-only.
#
# The source runner originally waited for any event carrying the boundary field.
# FIX1 narrowed that to the exact crash-point event. Runtime evidence then showed
# a second observation race at COMMIT_DECISION: the fault node emits the crash
# point first and the corresponding send-suppression event immediately after it,
# so the runner can parse the log in between those two writes.
#
# Patch only a temporary copy of the source runner. Wait for the exact crash point
# and then wait for the boundary-specific suppressed send before parsing events.
# All existing strict event-count, transfer-id, epoch, phase, snapshot, writer,
# identity, and recovery assertions remain unchanged.
$Original = Get-Content -LiteralPath $SourceRunner -Raw -ErrorAction Stop
$Needle = '        Wait-H42Marker $CrashLog (''"boundary":"'' + $Boundary + ''"'') $CrashProcess 50'
$Replacement = @'
        Wait-H42Marker $CrashLog '"event":"SM0_H4_MIXED_CRASH_POINT"' $CrashProcess 50
        if ($Boundary -eq "INFLIGHT_RETIRE") {
            Wait-H42Marker $SourceLog '"message_type":"PLAYER_HANDOFF_COMMIT"' $SourceProcess 20
        }
        elseif ($Boundary -eq "COMMIT_DECISION") {
            Wait-H42Marker $TargetLog '"message_type":"PLAYER_HANDOFF_COMMITTED"' $TargetProcess 20
            Wait-H42Marker $SourceLog '"message_type":"HANDOFF_REDIRECT"' $SourceProcess 20
        }
        elseif ($Boundary -eq "ACTIVATION") {
            Wait-H42Marker $TargetLog '"message_type":"ACTIVATE_ACK"' $TargetProcess 20
        }
'@.TrimEnd()

$Matches = ([regex]::Matches($Original, [regex]::Escape($Needle))).Count
if ($Matches -ne 1) {
    throw "SM0-H4.2 FIX2 expected exactly one broad boundary wait to replace, found $Matches."
}
$Patched = $Original.Replace($Needle, $Replacement)
if ($Patched -eq $Original) {
    throw "SM0-H4.2 FIX2 replacement produced no change."
}
if (([regex]::Matches($Patched, [regex]::Escape($Needle))).Count -ne 0) {
    throw "SM0-H4.2 FIX2 left the broad boundary wait in the patched runner."
}
if (([regex]::Matches($Patched, [regex]::Escape('Wait-H42Marker $CrashLog ''"event":"SM0_H4_MIXED_CRASH_POINT"'' $CrashProcess 50'))).Count -ne 1) {
    throw "SM0-H4.2 FIX2 did not produce exactly one exact crash-point wait."
}
foreach ($ExpectedMarker in @(
    '''"message_type":"PLAYER_HANDOFF_COMMIT"''',
    '''"message_type":"PLAYER_HANDOFF_COMMITTED"''',
    '''"message_type":"HANDOFF_REDIRECT"''',
    '''"message_type":"ACTIVATE_ACK"'''
)) {
    if (([regex]::Matches($Patched, [regex]::Escape($ExpectedMarker))).Count -lt 1) {
        throw "SM0-H4.2 FIX2 missing synchronization marker $ExpectedMarker."
    }
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "distributed-world-simulator-sm0-h42-fix2"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$TempRunner = Join-Path $TempRoot ("RUN_V0_SM0_MIXED_BOUNDARY_OUTAGE_ACCEPTANCE_FIX2_{0}_{1}.ps1" -f $PID, ([Guid]::NewGuid().ToString("N")))
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
    Write-Host "[SM0-H4.2-FIX2] Applying exact crash-point and suppression synchronization to temporary runner only."
    & $TempRunner @Invoke
    $Code = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $TempRunner -Force -ErrorAction SilentlyContinue
}

exit $Code
