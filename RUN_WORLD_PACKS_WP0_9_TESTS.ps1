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

    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "WORLD PACKS WP0.9 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
    }

    # POI library contract (manifest coverage, skinnability, degradation).
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/poi_library_selftest.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "POI library selftest failed (exit code $LASTEXITCODE)"
    }

    # Regression: every registered pack still builds through the library.
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/pack_profile_selftest.gd" -- "--all"
    if ($LASTEXITCODE -ne 0) {
        throw "Pack profile regression failed (exit code $LASTEXITCODE)"
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

Write-Host "WORLD PACKS WP0.9: PASS"
