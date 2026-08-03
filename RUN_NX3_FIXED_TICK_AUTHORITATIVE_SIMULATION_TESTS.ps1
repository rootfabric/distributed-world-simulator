param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Checkpoint = "v16.13.0-network-nx3-fixed-tick-authoritative-simulation"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath is required for $Checkpoint" }
$ProfileRoot = Join-Path $Root "artifacts/test-results/nx3-fixed-tick-$PID"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
$OriginalEnvironment = @{}
foreach ($Name in @("APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","BREAKPOINT_RUNTIME_DISABLED","BREAKPOINT_RUNTIME_PORT","GODOT_SILENCE_ROOT_WARNING","TERM")) {
    $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}
function Invoke-GodotSafe {
    param([string]$Name, [string[]]$Arguments)
    $Profile = Join-Path $ProfileRoot $Name
    $Data = Join-Path $Profile "data"; $Config = Join-Path $Profile "config"; $Cache = Join-Path $Profile "cache"
    New-Item -ItemType Directory -Force -Path $Data,$Config,$Cache | Out-Null
    $env:APPDATA=$Data; $env:LOCALAPPDATA=$Data; $env:XDG_DATA_HOME=$Data; $env:XDG_CONFIG_HOME=$Config; $env:XDG_CACHE_HOME=$Cache
    $env:BREAKPOINT_RUNTIME_DISABLED="1"; $env:GODOT_SILENCE_ROOT_WARNING="1"; $env:TERM="xterm"
    Remove-Item Env:BREAKPOINT_RUNTIME_PORT -ErrorAction SilentlyContinue
    Write-Host "`n[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference=$ErrorActionPreference
    $NativePreference=Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference=if($null -ne $NativePreference){$NativePreference.Value}else{$null}
    try {
        $ErrorActionPreference="Continue"
        if($null -ne $NativePreference){Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false}
        $Output=& $GodotPath @Arguments 2>&1; $ExitCode=$LASTEXITCODE; $Output | ForEach-Object { Write-Host $_ }
    } finally {
        $ErrorActionPreference=$PreviousErrorActionPreference
        if($null -ne $NativePreference){Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference}
    }
    $Text=$Output -join "`n"
    if($ExitCode -ne 0 -or $Text -cmatch "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)"){throw "NX3 fixed-tick step failed: $Name"}
}
try {
    Invoke-GodotSafe "editor-import" @("--headless","--editor","--path",$Root,"--import","--quit")
    Invoke-GodotSafe "preparation-contracts" @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_network_experience_preparation.gd")
    Invoke-GodotSafe "baseline-contracts" @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_observability_baseline.gd")
    Invoke-GodotSafe "nx1-contracts" @("--headless","--path",$Root,"--script","res://tests/network/test_nx1_deterministic_network_condition_simulator.gd")
    Invoke-GodotSafe "nx2-contracts" @("--headless","--path",$Root,"--script","res://tests/network/test_nx2_realtime_traffic_separation.gd")
    Invoke-GodotSafe "nx3-contracts" @("--headless","--path",$Root,"--script","res://tests/network/test_nx3_fixed_tick_authoritative_simulation.gd")
    Invoke-GodotSafe "compatibility-regression" @("--headless","--path",$Root,"--script","res://tests/network/test_nx0_observability_handshake_processes.gd")
    Invoke-GodotSafe "conditioned-enet-processes" @("--headless","--path",$Root,"--script","res://tests/network/test_nx1_network_condition_processes.gd")
    Invoke-GodotSafe "physical-channel-processes" @("--headless","--path",$Root,"--script","res://tests/network/test_nx2_physical_channel_processes.gd")
    Invoke-GodotSafe "nx3-playable-processes" @("--headless","--path",$Root,"--script","res://tests/runtime/test_m7_playable_networked_processes.gd")
    Invoke-GodotSafe "nx3-recovery-processes" @("--headless","--path",$Root,"--script","res://tests/runtime/test_m7_playable_networked_recovery_processes.gd")
} finally {
    foreach($Name in $OriginalEnvironment.Keys){$Value=$OriginalEnvironment[$Name]; if($null -eq $Value){Remove-Item "Env:$Name" -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($Name,$Value,"Process")}}
}
Write-Host "`nNX3 fixed-tick authoritative simulation: PASS (11/11) [$Checkpoint]" -ForegroundColor Green
