[CmdletBinding()]
param(
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [ValidateRange(2, 1000)][int]$RequireHandoffs = 10,
    [string]$ProjectRoot = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGraphical = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$ErrorActionPreference = "Stop"
$Runner = Join-Path $PSScriptRoot "RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "SM0 controlled WAN matrix runner is missing: $Runner"
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$ExitCode = 1
try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    Write-Host "[SM0-P4] Prewarmed fast handoff ENABLED for WAN matrix." -ForegroundColor Cyan
    & $Runner @PSBoundParameters
    $ExitCode = $LASTEXITCODE
}
finally {
    if ($HadP4) { $env:SM0_P4_FAST_HANDOFF = $PreviousP4 }
    else { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue }
}

exit $ExitCode
