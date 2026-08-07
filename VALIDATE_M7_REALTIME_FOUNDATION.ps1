param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$IncludeTwoClientProcess
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$Arguments)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $Output = @(& $Godot @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    foreach ($Line in $Output) { Write-Host $Line }
    $Text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    foreach ($Pattern in @("SCRIPT ERROR:", "Parse Error:", "Compile Error:", "Failed to load script")) {
        if ($Text.Contains($Pattern)) {
            throw "$Name emitted fatal Godot script diagnostics: $Pattern"
        }
    }
    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode"
    }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

Write-Host "[Accepted inventory regression]" -ForegroundColor Cyan
& (Join-Path $ProjectRoot "VALIDATE_M7_NETWORK_ITEM_REPLICA.ps1") -GodotPath $Godot

Invoke-GodotCheck -Name "Accepted inventory fix8 direct regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/ui/test_inventory_network_rev6_fix8.gd"
)

Invoke-GodotCheck -Name "NX3 fixed-tick regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx3_fixed_tick_authoritative_simulation.gd"
)

Invoke-GodotCheck -Name "NX4 prediction regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx4_client_prediction_reconciliation.gd"
)

Invoke-GodotCheck -Name "M7 realtime backpressure contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_realtime_backpressure_foundation.gd"
)

if ($IncludeTwoClientProcess) {
    Invoke-GodotCheck -Name "M7 two-client graphical process regression" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/runtime/test_m7_playable_networked_processes.gd"
    )
}

Write-Host ""
Write-Host "M7 realtime foundation validation passed." -ForegroundColor Green
if (-not $IncludeTwoClientProcess) {
    Write-Host "Run again with -IncludeTwoClientProcess for the multi-process acceptance gate." -ForegroundColor Yellow
}
