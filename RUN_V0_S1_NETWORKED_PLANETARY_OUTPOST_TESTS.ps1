$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @($env:GODOT_BIN)
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)
$Godot = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Godot) {
    throw "Double-precision Godot was not found. Set GODOT_BIN."
}

$Tests = @(
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_v0_s1_mvp_launch_options.gd",
    "res://tests/runtime/test_v0_s1_mvp_fixed_tick_movement.gd",
    "res://tests/runtime/test_v0_s1_local_two_player_contract.gd",
    "res://tests/runtime/test_mvp_procedural_planet_spawn.gd",
    "res://tests/runtime/test_mvp_earth_outpost_authority.gd",
    "res://tests/runtime/test_mvp_m3_construction_replication_bridge.gd",
    "res://tests/runtime/test_mvp_earth_c22_construction_presentation.gd",
    "res://tests/runtime/test_mvp_earth_m3_spectator.gd",
    "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd"
)

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogRoot = Join-Path $Root "artifacts\test-results\v0-s1-mvp-focused-$RunId"
$ProfileRoot = Join-Path $LogRoot "profiles"
New-Item -ItemType Directory -Force -Path $LogRoot,$ProfileRoot | Out-Null

$OriginalEnvironment = @{}
foreach ($Name in @(
    "HOME","USERPROFILE","APPDATA","LOCALAPPDATA",
    "XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME",
    "BREAKPOINT_RUNTIME_DISABLED","BREAKPOINT_RUNTIME_PORT",
    "GODOT_SILENCE_ROOT_WARNING"
)) {
    $OriginalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}

function Invoke-GodotSafe {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$TestHome
    )

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
    $LogFile = Join-Path $LogRoot "$Name.log"

    $OldPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $OldNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        $Output = & $Godot @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
        $Output | Tee-Object -FilePath $LogFile | ForEach-Object { Write-Host $_ }
    }
    finally {
        $ErrorActionPreference = $OldPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $OldNativePreference
        }
    }

    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -cmatch "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)") {
        throw "V0-S1 MVP validation failed: $Name. Log: $LogFile"
    }
}

try {
    $GodotVersion = (& $Godot --version 2>&1 | Out-String).Trim()
    $GitHead = (& git -C $Root rev-parse HEAD 2>&1 | Out-String).Trim()
    $GodotVersion | Set-Content -Encoding UTF8 (Join-Path $LogRoot "godot-version.txt")
    $GitHead | Set-Content -Encoding UTF8 (Join-Path $LogRoot "git-head.txt")

    Invoke-GodotSafe `
        -Name "editor-import" `
        -Arguments @("--headless","--editor","--path",$Root,"--quit") `
        -TestHome (Join-Path $ProfileRoot "editor-import")

    foreach ($Test in $Tests) {
        $Name = [IO.Path]::GetFileNameWithoutExtension($Test)
        Invoke-GodotSafe `
            -Name $Name `
            -Arguments @("--headless","--path",$Root,"--script",$Test) `
            -TestHome (Join-Path $ProfileRoot $Name)
    }
}
finally {
    foreach ($Name in $OriginalEnvironment.Keys) {
        $Value = $OriginalEnvironment[$Name]
        if ($null -eq $Value) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        }
    }
}

Write-Host ""
Write-Host "V0-S1 networked planetary outpost focused validation: PASS ($($Tests.Count)/$($Tests.Count))" -ForegroundColor Green
Write-Host "Logs: $LogRoot"
