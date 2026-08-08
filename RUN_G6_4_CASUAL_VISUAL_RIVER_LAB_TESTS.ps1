param(
    [string]$GodotPath = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    throw "GodotPath is required. Pass -GodotPath or set GODOT_BIN."
}
if (-not (Test-Path $GodotPath)) {
    throw "Godot binary not found: $GodotPath"
}

$HadGodotBin = Test-Path Env:\GODOT_BIN
$PreviousGodotBin = $env:GODOT_BIN
try {
    $env:GODOT_BIN = $GodotPath

    Write-Host "=== G6.3 accepted dependency gate ==="
    & "$PSScriptRoot\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1"
    if (-not $?) {
        throw "G6.3 accepted dependency gate failed"
    }

    Write-Host "=== G6.4 source / P0 contract gate ==="
    & $GodotPath --headless --path $PSScriptRoot --script res://tests/procedural/hydrology/g6_4_casual_visual_river_lab_acceptance.gd
    if ($LASTEXITCODE -ne 0) {
        throw "G6.4 visual river lab contract gate failed"
    }

    Write-Host "=== G6.4 headless scene smoke ==="
    $SceneLines = @()
    & $GodotPath --headless --path $PSScriptRoot --scene "res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn" --quit-after 2 2>&1 | Tee-Object -Variable SceneLines
    $SceneExitCode = $LASTEXITCODE
    $SceneText = ($SceneLines | Out-String)
    if ($SceneExitCode -ne 0) {
        throw "G6.4 visual river lab headless smoke failed with exit code $SceneExitCode"
    }
    if ($SceneText -match "(?m)^(SCRIPT ERROR:|ERROR: Failed to load script)") {
        throw "G6.4 visual river lab headless smoke reported a script parse/load error"
    }
    if ($SceneText -notmatch [regex]::Escape("G6.4 Casual Visual River Lab: PASS")) {
        throw "G6.4 visual river lab headless smoke did not emit its explicit PASS marker"
    }

    Write-Host "G6.4 Casual Visual River Lab automated gate passed."
    Write-Host "Manual graphical observation is still required before G6.4 acceptance."
}
finally {
    if ($HadGodotBin) { $env:GODOT_BIN = $PreviousGodotBin }
    else { Remove-Item Env:\GODOT_BIN -ErrorAction SilentlyContinue }
}

exit 0
