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

$HardenedRunner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE_R2.ps1"
if (-not (Test-Path -LiteralPath $HardenedRunner -PathType Leaf)) {
    throw "Hardened SM0 runner is missing: $HardenedRunner"
}

# Stop remains a lifecycle operation on the bounded two-authority launcher.
if ($Stop) {
    & $HardenedRunner @PSBoundParameters
    exit $LASTEXITCODE
}

# The documented -Final command is now the canonical integrated closure gate.
# The integrated runner calls R2 directly for its fixed 20-handoff baseline,
# so this delegation cannot recurse back into this wrapper.
if ($Final) {
    $FinalRunner = Join-Path $PSScriptRoot "RUN_V0_SM0_FINAL_ACCEPTANCE.ps1"
    if (-not (Test-Path -LiteralPath $FinalRunner -PathType Leaf)) {
        throw "Integrated SM0 FINAL runner is missing: $FinalRunner"
    }

    $FinalArgs = @{
        ProjectRoot = $ProjectRoot
        GodotExe = $GodotExe
        TimeoutSeconds = [Math]::Max(180, $TimeoutSeconds)
    }
    if ($AllowDirty) { $FinalArgs["AllowDirty"] = $true }

    & $FinalRunner @FinalArgs
    exit $LASTEXITCODE
}

& $HardenedRunner @PSBoundParameters
exit $LASTEXITCODE
