param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$FocusedOnly,
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

Write-Host "M7 FIX5 world-item consistency validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX5 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX5 world-item consistency contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_world_item_consistency_fix5.gd"
)

Invoke-GodotCheck -Name "NX6 predicted item interaction regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx6_predicted_item_interactions.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX4 + accepted inventory/network baseline]" -ForegroundColor Cyan
    if ($IncludeTwoClientProcess) {
        & (Join-Path $ProjectRoot "VALIDATE_M7_REALTIME_FOUNDATION.ps1") `
            -GodotPath $Godot `
            -IncludeTwoClientProcess
    }
    else {
        & (Join-Path $ProjectRoot "VALIDATE_M7_REALTIME_FOUNDATION.ps1") `
            -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 realtime foundation baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX5 world-item consistency validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly skips the accepted inventory/FIX4 baseline." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess for the existing multi-process regression as well." -ForegroundColor Yellow
}
Write-Host "Manual graphical acceptance still requires two clients repeatedly dropping/picking the same WORLD items and comparing pose/rotation." -ForegroundColor Yellow
