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

Write-Host "M7 FIX7 smooth prediction validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX7 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX7 focused smooth-prediction contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_smooth_prediction_fix7.gd"
)

Invoke-GodotCheck -Name "NX4 prediction/reconciliation regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_nx4_client_prediction_reconciliation.gd"
)

Invoke-GodotCheck -Name "FIX6 server realtime hot-path regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_realtime_backpressure_foundation.gd"
)

Invoke-GodotCheck -Name "FIX6 graphical client telemetry regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix6_client_telemetry.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX6 + FIX5 + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix6Runner = Join-Path $ProjectRoot "VALIDATE_M7_RUNTIME_PERFORMANCE_FIX6.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix6Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix6Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX6/full accepted baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX7 smooth prediction validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly checks parser/composition, FIX7 policies, NX4, and FIX6 realtime regressions only." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Final FIX7 acceptance still requires a >=5 minute two-client LOCAL movement/item stress run and ANALYZE_M7_FIX7_STRESS.ps1 PASS." -ForegroundColor Yellow
