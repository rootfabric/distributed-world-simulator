param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Checkpoint = "v16.10.6-architecture-a3-single-server-multiplayer"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath is required for $Checkpoint" }

$Tests = @(
    "res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd",
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_m1_networked_gameplay_contracts.gd",
    "res://tests/runtime/test_m1_unified_networked_gameplay_service.gd",
    "res://tests/runtime/test_m2_graphical_client_contracts.gd",
    "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd",
    "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd",
    "res://tests/runtime/test_m5_graphical_acceptance_contracts.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_processes.gd",
    "res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
    "res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd"
)

$ProfileRoot = Join-Path $Root "artifacts/test-results/a3-focused-profile-$PID"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
$OriginalEnvironment = @{}
foreach ($Name in @("HOME","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","BREAKPOINT_RUNTIME_DISABLED","BREAKPOINT_RUNTIME_PORT","GODOT_SILENCE_ROOT_WARNING")) {
    $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Invoke-GodotSafe {
    param([string]$Name, [string[]]$Arguments, [string]$TestHome)
    $Data = Join-Path $TestHome "data"
    $Config = Join-Path $TestHome "config"
    $Cache = Join-Path $TestHome "cache"
    New-Item -ItemType Directory -Force -Path $Data,$Config,$Cache | Out-Null
    $env:HOME = $TestHome
    $env:APPDATA = $Data
    $env:LOCALAPPDATA = $Data
    $env:XDG_DATA_HOME = $Data
    $env:XDG_CONFIG_HOME = $Config
    $env:XDG_CACHE_HOME = $Cache
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    $env:GODOT_SILENCE_ROOT_WARNING = "1"
    Remove-Item Env:BREAKPOINT_RUNTIME_PORT -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $OldPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $OldNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false }
        $Output = & $GodotPath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
        $Output | ForEach-Object { Write-Host $_ }
    }
    finally {
        $ErrorActionPreference = $OldPreference
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $OldNativePreference }
    }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -cmatch "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)") {
        throw "A3 architecture step failed: $Name"
    }
}

try {
    Invoke-GodotSafe -Name "editor_import" -Arguments @("--headless","--editor","--path",$Root,"--quit") -TestHome (Join-Path $ProfileRoot "editor-import")
    foreach ($Test in $Tests) {
        $Name = [IO.Path]::GetFileNameWithoutExtension($Test)
        Invoke-GodotSafe -Name $Name -Arguments @("--headless","--path",$Root,"--script",$Test) -TestHome (Join-Path $ProfileRoot $Name)
    }
}
finally {
    foreach ($Name in $OriginalEnvironment.Keys) {
        $Value = $OriginalEnvironment[$Name]
        if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($Name, $Value, "Process") }
    }
}

Write-Host ""
Write-Host "A3 single-server multiplayer architecture: PASS ($($Tests.Count)/$($Tests.Count)) [$Checkpoint]" -ForegroundColor Green
