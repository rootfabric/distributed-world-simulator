param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Checkpoint = "v16.10.6.1-testing-m7-playable-networked-playground"
if ([string]::IsNullOrWhiteSpace($GodotPath)) { throw "GodotPath is required for $Checkpoint" }

$Tests = @(
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_m7_playable_networked_playground.gd",
    "res://tests/runtime/test_m7_playable_networked_processes.gd",
    "res://tests/runtime/test_m7_playable_networked_recovery_processes.gd",
    "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd",
    "res://tests/runtime/test_m4_networked_playground_extension.gd",
    "res://tests/runtime/test_m5_graphical_acceptance_contracts.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd",
    "res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd",
    "res://tests/ui/test_inventory_interaction_profiles.gd",
    "res://tests/ui/test_inventory_seven_days_interface.gd",
    "res://tests/items/test_player_inventory_flow.gd",
    "res://tests/items/test_item_placement_and_admin.gd"
)

$ProfileRoot = Join-Path $Root "artifacts/test-results/m7-focused-profile-$PID"
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
$OriginalEnvironment = @{}
foreach ($Name in @("HOME","USERPROFILE","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","BREAKPOINT_RUNTIME_DISABLED","BREAKPOINT_RUNTIME_PORT","GODOT_SILENCE_ROOT_WARNING")) {
    $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Invoke-GodotSafe {
    param([string]$Name, [string[]]$Arguments, [string]$TestHome)
    $Data = Join-Path $TestHome "data"
    $Config = Join-Path $TestHome "config"
    $Cache = Join-Path $TestHome "cache"
    New-Item -ItemType Directory -Force -Path $Data,$Config,$Cache | Out-Null
    $env:HOME = $TestHome
    $env:USERPROFILE = $TestHome
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
        throw "M7 playable network step failed: $Name"
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
Write-Host "M7 playable networked playground: PASS ($($Tests.Count)/$($Tests.Count)) [$Checkpoint]" -ForegroundColor Green
