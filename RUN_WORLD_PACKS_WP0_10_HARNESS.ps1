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
        Write-Host "WORLD PACKS WP0.10 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
    }

    # Full gate chain: schema, license ledger, POI library, pack profiles.
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/validate_pack.gd" -- "--dir=res://config/world_packs/packs"
    if ($LASTEXITCODE -ne 0) {
        throw "Pack manifest schema validation failed (exit code $LASTEXITCODE)"
    }
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/check_asset_ledger.gd" -- "--root=res://assets/third_party"
    if ($LASTEXITCODE -ne 0) {
        throw "License ledger check failed (exit code $LASTEXITCODE)"
    }
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/poi_library_selftest.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "POI library selftest failed (exit code $LASTEXITCODE)"
    }
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/pack_profile_selftest.gd" -- "--all"
    if ($LASTEXITCODE -ne 0) {
        throw "Pack profile selftest failed (exit code $LASTEXITCODE)"
    }

    # Comparison harness: captures per-pack records and boots the gallery.
    & $GodotPath --headless --path $RootDir --script "res://tools/world_packs/gallery_comparison_harness.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Gallery comparison harness failed (exit code $LASTEXITCODE)"
    }

    $CapturePath = Join-Path $RootDir "validation\world_packs\wp0_10_gallery_comparison.v1.json"
    if (-not (Test-Path -LiteralPath $CapturePath -PathType Leaf)) {
        throw "Harness capture record was not written: $CapturePath"
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

Write-Host "WORLD PACKS WP0.10: PASS"
