param(
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$PackId = "ALL"
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
        Write-Host "WORLD PACKS profiles preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
    }

    # 1. All pack manifests must satisfy the WP0.1 schema contract.
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/validate_pack.gd" -- "--dir=res://config/world_packs/packs"
    if ($LASTEXITCODE -ne 0) {
        throw "Pack manifest schema validation failed (exit code $LASTEXITCODE)"
    }

    # 2. Presentation profile selftest: one pack or all packs.
    $Selftest = "res://tools/world_packs/pack_profile_selftest.gd"
    if ($PackId -eq "ALL") {
        & $GodotPath --headless --path $RootDir --script $Selftest -- "--all"
    }
    else {
        & $GodotPath --headless --path $RootDir --script $Selftest -- "--pack=$PackId"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Pack profile selftest failed (exit code $LASTEXITCODE)"
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

Write-Host "WORLD PACKS PROFILES ($PackId): PASS"
