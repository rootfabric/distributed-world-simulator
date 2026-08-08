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

Write-Host "M7 FIX8 prediction clock validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX8 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX8 focused prediction-clock contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_prediction_clock_fix8.gd"
)

Invoke-GodotCheck -Name "FIX7 smooth-prediction regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_smooth_prediction_fix7.gd"
)

Invoke-GodotCheck -Name "NX4 prediction/reconciliation regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx4_client_prediction_reconciliation.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX7 + FIX6 + FIX5 + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix7Runner = Join-Path $ProjectRoot "VALIDATE_M7_SMOOTH_PREDICTION_FIX7.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix7Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix7Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX7/full accepted baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX8 prediction clock validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly checks parser/composition, FIX8, FIX7, and NX4 contracts only." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Manual acceptance: repeat the two-client LOCAL movement/item run and compare prediction error/corrections plus remote moving-buffer underrun telemetry." -ForegroundColor Yellow
