[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Handoffs = 4,

    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,

    [string]$ProjectRoot = "",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$Runner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "SM0 acceptance runner is missing: $Runner"
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$ExitCode = 1
try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    Write-Host "[SM0-P4] Prewarmed fast handoff ENABLED for this run." -ForegroundColor Cyan
    & $Runner @PSBoundParameters
    $ExitCode = $LASTEXITCODE
}
finally {
    if ($HadP4) { $env:SM0_P4_FAST_HANDOFF = $PreviousP4 }
    else { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue }
}

exit $ExitCode
