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

    # A fresh git worktree has no .godot/uid_cache.bin yet. Launch a focused
    # --script run only after the normal Godot import/UID cache exists, exactly
    # like the other RUN_* runners in this repository.
    if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
        Write-Host "WORLD PACKS WP0.1 preflight: initializing Godot import/UID cache"
        & $GodotPath --headless --path $RootDir --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot import/UID-cache preflight failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path -LiteralPath $UidCachePath -PathType Leaf)) {
            throw "Godot import preflight completed but UID cache was not created: $UidCachePath"
        }
    }

    $Validator = "res://tools/world_packs/validate_pack.gd"
    $ValidFixture = "res://tests/world_packs/fixtures/wp-demo-valid.v1.json"
    $InvalidFixtures = @(
        "res://tests/world_packs/fixtures/wp-demo-missing-required.v1.json",
        "res://tests/world_packs/fixtures/wp-demo-bad-identity.v1.json"
    )

    # 1. Usage contract: no arguments must exit with code 2.
    & $GodotPath --headless --path $RootDir --script $Validator
    if ($LASTEXITCODE -ne 2) {
        throw "WP0.1 validator usage contract broken: expected exit code 2, got $LASTEXITCODE"
    }

    # 2. A conforming manifest must pass.
    & $GodotPath --headless --path $RootDir --script $Validator -- "--pack=$ValidFixture"
    if ($LASTEXITCODE -ne 0) {
        throw "WP0.1 validator rejected the VALID fixture (exit code $LASTEXITCODE)"
    }

    # 3. Every known-invalid fixture must fail with exit code 1.
    foreach ($Fixture in $InvalidFixtures) {
        & $GodotPath --headless --path $RootDir --script $Validator -- "--pack=$Fixture"
        if ($LASTEXITCODE -eq 0) {
            throw "WP0.1 validator accepted an INVALID fixture: $Fixture"
        }
        if ($LASTEXITCODE -ne 1) {
            throw "WP0.1 validator did not fail cleanly on $Fixture (exit code $LASTEXITCODE)"
        }
    }

    # 4. Directory mode: a directory of valid manifests must pass as a batch.
    $DirTestRoot = Join-Path $RootDir "artifacts\world_packs_wp0_1_dir_mode"
    if (Test-Path -LiteralPath $DirTestRoot) {
        Remove-Item -LiteralPath $DirTestRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $DirTestRoot | Out-Null
    Copy-Item `
        (Join-Path $RootDir "tests\world_packs\fixtures\wp-demo-valid.v1.json") `
        (Join-Path $DirTestRoot "wp-dir-mode-a.v1.json")
    Copy-Item `
        (Join-Path $RootDir "tests\world_packs\fixtures\wp-demo-valid.v1.json") `
        (Join-Path $DirTestRoot "wp-dir-mode-b.v1.json")
    & $GodotPath --headless --path $RootDir --script $Validator -- "--dir=res://artifacts/world_packs_wp0_1_dir_mode"
    if ($LASTEXITCODE -ne 0) {
        throw "WP0.1 validator directory mode failed (exit code $LASTEXITCODE)"
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

Write-Host "WORLD PACKS WP0.1: PASS"
