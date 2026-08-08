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

Write-Host "M7 FIX9 client frame budget validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX9 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX9 focused frame-budget contracts" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_client_frame_budget_fix9.gd"
)

Invoke-GodotCheck -Name "FIX8 prediction-clock regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_prediction_clock_fix8.gd"
)

Invoke-GodotCheck -Name "FIX6 graphical telemetry regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_fix6_client_telemetry.gd"
)

Invoke-GodotCheck -Name "Accepted inventory fix8 regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/ui/test_inventory_network_rev6_fix8.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX8 + FIX7 + FIX6 + FIX5 + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix8Runner = Join-Path $ProjectRoot "VALIDATE_M7_PREDICTION_CLOCK_FIX8.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix8Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix8Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX8/full accepted baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX9 client frame budget validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly validates FIX9 instrumentation/layout suppression plus direct FIX8/FIX6/inventory regressions." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Final FIX9 acceptance still requires a >=5 minute two-client LOCAL movement/item stress run and ANALYZE_M7_FIX9_RESULTS.ps1 review of phase peaks." -ForegroundColor Yellow
