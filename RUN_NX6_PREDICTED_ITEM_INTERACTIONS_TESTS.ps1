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
$Godot = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $Godot) { throw "Double-precision Godot not found. Set GODOT_BIN or pass -GodotPath." }
$Godot = (Resolve-Path $Godot).Path
$ResultRoot = Join-Path $ProjectRoot ("artifacts/test-results/nx6-fix3-{0}" -f $PID)
$DataRoot = Join-Path $ResultRoot "data"
$ConfigRoot = Join-Path $ResultRoot "config"
$CacheRoot = Join-Path $ResultRoot "cache"
foreach ($Path in @($ResultRoot, $DataRoot, $ConfigRoot, $CacheRoot)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
$Names = @("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "GODOT_BIN")
$Saved = @{}
foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
try {
    $env:APPDATA = $DataRoot
    $env:LOCALAPPDATA = $DataRoot
    $env:XDG_DATA_HOME = $DataRoot
    $env:XDG_CONFIG_HOME = $ConfigRoot
    $env:XDG_CACHE_HOME = $CacheRoot
    $env:GODOT_BIN = $Godot
    function Invoke-Nx6Step {
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
        $Output | Set-Content -Path (Join-Path $ResultRoot "$Name.log") -Encoding UTF8
        if ($RawExitCode -ne 0 -or $Output -match '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)') { throw "$Name failed" }
        Write-Host "${Name}: PASS" -ForegroundColor Green
    }
    Invoke-Nx6Step "editor_import" @("--headless", "--editor", "--path", $ProjectRoot, "--quit")
    Invoke-Nx6Step "nx6_contracts" @("--headless", "--path", $ProjectRoot, "--script", "res://tests/network/test_nx6_predicted_item_interactions.gd")
    Invoke-Nx6Step "nx6_integration" @("--headless", "--path", $ProjectRoot, "--script", "res://tests/network/test_nx6_predicted_item_interactions_integration.gd")
    Invoke-Nx6Step "m7_playable_contracts" @("--headless", "--path", $ProjectRoot, "--script", "res://tests/runtime/test_m7_playable_networked_playground.gd")

    # Fix3 keeps the graphical M7 multiprocess suite to a mandatory gate.
    & (Join-Path $ProjectRoot "RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.ps1") -GodotPath $Godot
    if ($LASTEXITCODE -ne 0) { throw "M7 graphical multiprocess regression failed" }
    if ($IncludeGraphicalProcess) {
        Write-Host "IncludeGraphicalProcess is retained for compatibility; M7 multiprocess already ran as a mandatory fix3 gate." -ForegroundColor DarkGray
    }
    if ($IncludeAcceptedRegression) {
        & (Join-Path $ProjectRoot "RUN_NX5_REMOTE_SNAPSHOT_INTERPOLATION_TESTS.ps1") -GodotPath $Godot -IncludeAcceptedRegression
        if ($LASTEXITCODE -ne 0) { throw "NX5 accepted regression failed" }
    }
    Write-Host "NX6 predicted item interactions fix3: PASS (5/5 mandatory)" -ForegroundColor Green
    Write-Host "Logs: $ResultRoot"
}
finally {
    foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], "Process") }
}
