[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [switch]$Visual,
    [int]$VisualHoldSeconds = 15,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot") -PathType Leaf)) { throw "Godot project.godot missing: $ProjectRoot" }
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) { throw "Godot 4.7.1 double console executable missing: $GodotExe" }
if ($Visual -and -not (Test-Path -LiteralPath $GodotGuiExe -PathType Leaf)) { throw "Godot 4.7.1 double GUI executable missing: $GodotGuiExe" }
if ($VisualHoldSeconds -lt 0) { throw "VisualHoldSeconds must be >= 0." }

$GitHead = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) { throw "Unable to resolve exact git HEAD." }
$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) { throw "git status failed for $ProjectRoot" }
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) { throw "P8.1 visual/reference-frame gate requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")" }

$PreviousBridgeDisabled = $env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED = "1"

try {
    Write-Host "[SM0-P8.1] Compile-checking repaired observer and focused regression..."
    foreach ($ScriptPath in @(
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd",
        "res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd",
        "res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd"
    )) {
        & $GodotExe --headless --path $ProjectRoot --check-only --script $ScriptPath
        if ($LASTEXITCODE -ne 0) { throw "P8.1 compile check failed: $ScriptPath" }
    }

    Write-Host "[SM0-P8.1] Running focused reference-frame regression..."
    $FocusedOutput = @(& $GodotExe --headless --path $ProjectRoot --script res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd 2>&1)
    $FocusedOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "SM0 P8.1 focused reference-frame regression failed." }
    if (-not (($FocusedOutput -join "`n") -match 'SM0 P8\.1 visual reference-frame repair: PASS \(33 assertions\)')) {
        throw "SM0 P8.1 focused regression did not emit the exact 33-assertion PASS marker."
    }

    Write-Host "[SM0-P8.1] Re-running inherited full P8 authority/process gate with repaired observer..."
    $P8Runner = Join-Path $ProjectRoot "RUN_V0_SM0_P8_MOVING_NESTED_ISLAND.ps1"
    if (-not (Test-Path -LiteralPath $P8Runner -PathType Leaf)) { throw "Inherited P8 runner missing: $P8Runner" }
    & $P8Runner -ProjectRoot $ProjectRoot -GodotExe $GodotExe -GodotGuiExe $GodotGuiExe -Visual:$Visual -VisualHoldSeconds $VisualHoldSeconds -AllowDirty:$AllowDirty
    if ($LASTEXITCODE -ne 0) { throw "Inherited SM0 P8 gate failed under P8.1 repaired observer." }

    $StatusAfter = @(& git -C $ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw "git status failed after P8.1 gate." }
    if (-not $AllowDirty -and ($StatusAfter -join "`n") -ne ($StatusBefore -join "`n")) { throw "P8.1 gate modified the source worktree." }

    Write-Host ""
    Write-Host "SM0-P8.1 visual/reference-frame repair: PASS"
    Write-Host "  HEAD       : $GitHead"
    Write-Host "  frame      : persistent ShipRoot owns ship + player visuals"
    Write-Host "  transform  : player rendered from ship-local coordinates"
    Write-Host "  yaw        : Godot ShipRoot uses -world_yaw to match canonical contract composition"
    Write-Host "  smoothing  : ShipRoot + local player motion use frame-coherent interpolation"
    Write-Host "  authority  : inherited P8 A -> C -> A semantics unchanged"
    Write-Host "  focused    : PASS (33 assertions)"
    Write-Host "  visual mode: $([bool]$Visual)"
}
finally {
    if ($null -eq $PreviousBridgeDisabled) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $PreviousBridgeDisabled
    }
}
