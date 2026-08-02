param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Checkpoint = "v16.11.0-network-nx1-deterministic-condition-simulator"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath is required for $Checkpoint" }

$ProfileRoot = Join-Path $Root "artifacts/test-results/nx1-network-condition-$PID"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
$OriginalEnvironment = @{}
foreach ($Name in @("APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","BREAKPOINT_RUNTIME_DISABLED","BREAKPOINT_RUNTIME_PORT","GODOT_SILENCE_ROOT_WARNING","TERM")) {
    $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Invoke-GodotSafe {
    param([string]$Name, [string[]]$Arguments)
    $Profile = Join-Path $ProfileRoot $Name
    $Data = Join-Path $Profile "data"
    $Config = Join-Path $Profile "config"
    $Cache = Join-Path $Profile "cache"
    New-Item -ItemType Directory -Force -Path $Data,$Config,$Cache | Out-Null
    $env:APPDATA = $Data
    $env:LOCALAPPDATA = $Data
    $env:XDG_DATA_HOME = $Data
    $env:XDG_CONFIG_HOME = $Config
    $env:XDG_CACHE_HOME = $Cache
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_SILENCE_ROOT_WARNING = "1"
    $env:TERM = "xterm"
    Remove-Item Env:BREAKPOINT_RUNTIME_PORT -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false }
        $Output = & $GodotPath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
        $Output | ForEach-Object { Write-Host $_ }
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference }
    }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -cmatch "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)") {
        throw "NX1 network condition step failed: $Name"
    }
}

try {
    Invoke-GodotSafe -Name "editor-import" -Arguments @("--headless","--editor","--path",$Root,"--import","--quit")
    Invoke-GodotSafe -Name "preparation-contracts" -Arguments @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_network_experience_preparation.gd")
    Invoke-GodotSafe -Name "baseline-contracts" -Arguments @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_observability_baseline.gd")
    Invoke-GodotSafe -Name "nx1-contracts" -Arguments @("--headless","--path",$Root,"--script","res://tests/network/test_nx1_deterministic_network_condition_simulator.gd")
    Invoke-GodotSafe -Name "compatibility-regression" -Arguments @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_observability_handshake_processes.gd")
    Invoke-GodotSafe -Name "conditioned-enet-processes" -Arguments @("--headless","--path",$Root,"--script","res://tests/network/test_nx1_network_condition_processes.gd")
}
finally {
    foreach ($Name in $OriginalEnvironment.Keys) {
        $Value = $OriginalEnvironment[$Name]
        if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($Name, $Value, "Process") }
    }
}

Write-Host ""
Write-Host "NX1 deterministic network condition simulator: PASS (6/6) [$Checkpoint]" -ForegroundColor Green
