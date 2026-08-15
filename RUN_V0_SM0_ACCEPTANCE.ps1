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

$Runner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE_R2.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "Hardened SM0 runner is missing: $Runner"
}

& $Runner @PSBoundParameters
exit $LASTEXITCODE
