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
        Write-Host "WORLD PACKS WP0.2 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
            throw "Godot import preflight completed but UID cache was not created: $UidCachePath"
        }
    }

    $Checker = "res://tools/world_packs/check_asset_ledger.gd"

    # 1. Real third-party root: must pass. Currently zero third-party assets
    #    are committed, so the enforced-empty result is the expected baseline.
    & $GodotPath --headless --path $RootDir --script $Checker -- "--root=res://assets/third_party"
    if ($LASTEXITCODE -ne 0) {
        throw "WP0.2 ledger check failed on assets/third_party (exit code $LASTEXITCODE)"
    }

    # 2. Complete provenance fixture must pass.
    & $GodotPath --headless --path $RootDir --script $Checker -- "--root=res://tests/world_packs/ledger_fixtures/ok"
    if ($LASTEXITCODE -ne 0) {
        throw "WP0.2 ledger checker rejected a COMPLETE provenance fixture (exit code $LASTEXITCODE)"
    }

    # 3. Incomplete SOURCE.md fixture must fail with exit code 1.
    & $GodotPath --headless --path $RootDir --script $Checker -- "--root=res://tests/world_packs/ledger_fixtures/bad/incomplete_record"
    if ($LASTEXITCODE -ne 1) {
        throw "WP0.2 ledger checker did not reject an INCOMPLETE SOURCE.md (exit code $LASTEXITCODE)"
    }

    # 4. Missing SOURCE.md fixture must fail with exit code 1.
    & $GodotPath --headless --path $RootDir --script $Checker -- "--root=res://tests/world_packs/ledger_fixtures/bad/no_record"
    if ($LASTEXITCODE -ne 1) {
        throw "WP0.2 ledger checker did not reject a MISSING SOURCE.md (exit code $LASTEXITCODE)"
    }

    # 5. Usage contract: unknown option must exit with code 2.
    & $GodotPath --headless --path $RootDir --script $Checker -- "--bogus=1"
    if ($LASTEXITCODE -ne 2) {
        throw "WP0.2 ledger checker usage contract broken: expected exit code 2, got $LASTEXITCODE"
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

Write-Host "WORLD PACKS WP0.2: PASS"
