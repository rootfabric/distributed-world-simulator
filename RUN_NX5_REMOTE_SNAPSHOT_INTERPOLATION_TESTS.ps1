param(
    [string]$GodotPath = "",
    [switch]$IncludeAcceptedRegression,
    [switch]$IncludeGraphicalProcess
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
)
foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $Command) { $Candidates += $Command.Source }
}
$Godot = $Candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
    Select-Object -Unique |
    Select-Object -First 1
if ($null -eq $Godot) { throw "Double-precision Godot not found. Set GODOT_BIN or pass -GodotPath." }
$Godot = (Resolve-Path $Godot).Path

$ResultRoot = Join-Path $ProjectRoot ("artifacts/test-results/nx5-{0}" -f $PID)
$DataRoot = Join-Path $ResultRoot "data"
$ConfigRoot = Join-Path $ResultRoot "config"
$CacheRoot = Join-Path $ResultRoot "cache"
foreach ($Path in @($ResultRoot, $DataRoot, $ConfigRoot, $CacheRoot)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}
$EnvironmentNames = @(
    "APPDATA",
    "LOCALAPPDATA",
    "XDG_DATA_HOME",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
    "GODOT_BIN"
)
$EnvironmentBackup = @{}
foreach ($Name in $EnvironmentNames) {
    $EnvironmentBackup[$Name] = [Environment]::GetEnvironmentVariable(
        $Name,
        [EnvironmentVariableTarget]::Process
    )
}

try {
    $env:APPDATA = $DataRoot
    $env:LOCALAPPDATA = $DataRoot
    $env:XDG_DATA_HOME = $DataRoot
    $env:XDG_CONFIG_HOME = $ConfigRoot
    $env:XDG_CACHE_HOME = $CacheRoot

    function Invoke-Nx5Step {
        param([string]$Name, [string[]]$Arguments)
        Write-Host "--- $Name ---" -ForegroundColor Cyan
        $Captured = @()
        $Previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & $Godot @Arguments 2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
            $RawExitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $Previous }
        $Output = ($Captured | Out-String)
        $Failed = $RawExitCode -ne 0 -or $Output -match '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
        $Output | Set-Content -Path (Join-Path $ResultRoot "$Name.log") -Encoding UTF8
        if ($Failed) { throw "$Name failed" }
        Write-Host "${Name}: PASS" -ForegroundColor Green
    }

    Invoke-Nx5Step -Name "editor_import" -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit")
    Invoke-Nx5Step -Name "nx5_contracts" -Arguments @("--headless", "--path", $ProjectRoot, "--script", "res://tests/network/test_nx5_remote_snapshot_interpolation.gd")
    Invoke-Nx5Step -Name "nx5_integration" -Arguments @("--headless", "--path", $ProjectRoot, "--script", "res://tests/network/test_nx5_remote_snapshot_interpolation_integration.gd")
    Invoke-Nx5Step -Name "m3_presenter_regression" -Arguments @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd")
    Invoke-Nx5Step -Name "m4_playground_regression" -Arguments @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/test_m4_networked_playground_extension.gd")

    if ($IncludeGraphicalProcess) {
        Invoke-Nx5Step -Name "m3_graphical_process" -Arguments @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/test_m3_graphical_multiplayer_processes.gd")
    }

    if ($IncludeAcceptedRegression) {
        & (Join-Path $ProjectRoot "RUN_NX4_CLIENT_PREDICTION_RECONCILIATION_TESTS.ps1") -GodotPath $Godot
        if ($LASTEXITCODE -ne 0) { throw "NX4 regression failed" }
        $env:GODOT_BIN = $Godot
        & (Join-Path $ProjectRoot "RUN_NETWORK_CONTRACT_TESTS.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Network regression failed" }
        & (Join-Path $ProjectRoot "RUN_WORLD_REGRESSION_TESTS.ps1")
        if ($LASTEXITCODE -ne 0) { throw "World regression failed" }
    }

    Write-Host "NX5 remote snapshot interpolation: PASS (5/5 focused)" -ForegroundColor Green
    Write-Host "Logs: $ResultRoot"

}
finally {
    foreach ($Name in $EnvironmentNames) {
        $PreviousValue = $EnvironmentBackup[$Name]
        if ($null -eq $PreviousValue) {
            Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -Path "Env:$Name" -Value $PreviousValue
        }
    }
}
