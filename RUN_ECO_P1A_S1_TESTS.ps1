param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UidCachePath = Join-Path $RootDir ".godot\uid_cache.bin"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot binary not found: $GodotPath"
}

$PreviousBreakpointDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    # A fresh git worktree has no .godot/uid_cache.bin yet. project.godot stores
    # BreakpointRuntimeBridge by uid://, so a direct --script launch before the
    # first import can resolve that autoload to an empty path and print misleading
    # Resource file not found / Failed to instantiate an autoload errors even
    # though the ECO test itself passes. Build the normal Godot import/UID cache
    # once before focused execution; this does not change ECO truth or test data.
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "ECO.P1A-S1 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
            throw "Godot import preflight completed but UID cache was not created: $UidCachePath"
        }
    }

    & $GodotPath --headless --path $RootDir --script "res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "ECO.P1A-S1 focused acceptance failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $PreviousBreakpointDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBreakpointDisabled
    }
}

Write-Host "ECO.P1A-S1 focused acceptance: PASS"
