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

Write-Host "M7 FIX6 runtime performance validation" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "FIX6 editor import/composition" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

Invoke-GodotCheck -Name "FIX6 realtime hot-path regression" -Arguments @(
    "--headless", "--path", $ProjectRoot,
    "--script", "res://tests/network/test_m7_realtime_backpressure_foundation.gd"
)

if (-not $FocusedOnly) {
    Write-Host ""
    Write-Host "[FIX5 correctness + accepted network/inventory baseline]" -ForegroundColor Cyan
    $Fix5Runner = Join-Path $ProjectRoot "VALIDATE_M7_WORLD_ITEM_CONSISTENCY_FIX5.ps1"
    if ($IncludeTwoClientProcess) {
        & $Fix5Runner -GodotPath $Godot -IncludeTwoClientProcess
    }
    else {
        & $Fix5Runner -GodotPath $Godot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "M7 FIX5/full network baseline failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "M7 FIX6 runtime performance validation passed." -ForegroundColor Green
if ($FocusedOnly) {
    Write-Host "FocusedOnly checks parser/composition and the FIX4/FIX6 realtime regression only." -ForegroundColor Yellow
}
elseif (-not $IncludeTwoClientProcess) {
    Write-Host "Run with -IncludeTwoClientProcess before manual acceptance." -ForegroundColor Yellow
}
Write-Host "Final acceptance still requires a long two-client LOCAL item stress run and review of SERVER_HEALTH/PREDICTION_HEALTH metrics." -ForegroundColor Yellow
