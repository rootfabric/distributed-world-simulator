[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(0, 1000)][int]$RequireRecoveries = 0,
    [ValidateRange(250, 5000)][int]$PhaseHoldMs = 250,
    [ValidateRange(250, 5000)][int]$OutageHoldMs = 250,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_GRAPHICAL_RECOVERY_LAB.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) { throw "SM0-P2.2 source graphical runner not found: $SourceRunner" }

$Original = Get-Content -LiteralPath $SourceRunner -Raw -ErrorAction Stop
$CompileNeedle = '    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd",'
$CompileReplacement = $CompileNeedle + "`n" + '    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd",' + "`n" + '    "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance_v2.gd",'
$ArgsNeedle = '        "--stop-file=$StopFile", "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot"'
$ArgsReplacement = '        "--stop-file=$StopFile", "--fault-profile=$FaultProfile", "--recovery-dir=$RecoveryRoot", "--recovery-performance=p22"'

$CompileMatches = ([regex]::Matches($Original, [regex]::Escape($CompileNeedle))).Count
$ArgsMatches = ([regex]::Matches($Original, [regex]::Escape($ArgsNeedle))).Count
if ($CompileMatches -ne 1) { throw "SM0-P2.2 expected exactly one recovery-chain compile line, found $CompileMatches." }
if ($ArgsMatches -ne 1) { throw "SM0-P2.2 expected exactly one server argument line, found $ArgsMatches." }
$Patched = $Original.Replace($CompileNeedle, $CompileReplacement).Replace($ArgsNeedle, $ArgsReplacement)
if ($Patched -eq $Original) { throw "SM0-P2.2 temporary runner patch produced no change." }
if (-not $Patched.Contains('--recovery-performance=p22')) { throw "SM0-P2.2 temporary runner does not contain explicit p22 mode." }

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "distributed-world-simulator-sm0-p22"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$TempRunner = Join-Path $TempRoot ("RUN_V0_SM0_GRAPHICAL_RECOVERY_PERFORMANCE_V2_{0}_{1}.ps1" -f $PID, ([Guid]::NewGuid().ToString("N")))
$Patched | Set-Content -LiteralPath $TempRunner -Encoding UTF8

$Invoke = @{
    RequireRecoveries = $RequireRecoveries
    PhaseHoldMs = $PhaseHoldMs
    OutageHoldMs = $OutageHoldMs
    ProjectRoot = $ProjectRoot
    GodotConsole = $GodotConsole
    GodotGraphical = $GodotGraphical
}
if ($Stop) { $Invoke.Stop = $true }
if ($Restart) { $Invoke.Restart = $true }
if ($AllowDirty) { $Invoke.AllowDirty = $true }

try {
    Write-Host "[SM0-P2.2] Bounded movement + bounded service/ownership/transfer replay enabled." -ForegroundColor Green
    Write-Host "[SM0-P2.2] Fast visual holds: phase=${PhaseHoldMs}ms outage=${OutageHoldMs}ms."
    & $TempRunner @Invoke
    $Code = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $TempRunner -Force -ErrorAction SilentlyContinue
}

exit $Code
