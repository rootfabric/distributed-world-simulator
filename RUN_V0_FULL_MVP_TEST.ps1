param(
    [ValidateRange(1, 86400)]
    [int]$SoakSeconds = 30,

    [switch]$Final,

    [string]$Driver = "res://tests/runtime/v0/v0_current_mvp_driver.gd"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$FinalSoakSeconds = 1800
if ($Final) {
    if (-not $PSBoundParameters.ContainsKey("SoakSeconds")) {
        $SoakSeconds = $FinalSoakSeconds
    }
    elseif ($SoakSeconds -lt $FinalSoakSeconds) {
        throw "Final V0 acceptance requires at least $FinalSoakSeconds soak seconds (30 minutes)."
    }
}

$Candidates = @($env:GODOT_BIN)
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    (Join-Path $Root "tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64")
)
$Godot = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Godot) {
    throw "Double-precision Godot was not found. Set GODOT_BIN."
}

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$LogRoot = Join-Path $Root "artifacts\test-results\v0-full-mvp-$RunId"
$ProfileRoot = Join-Path $LogRoot "profiles"
$ScenarioSummaryPath = Join-Path $LogRoot "scenario-summary.json"
$RunnerSummaryPath = Join-Path $LogRoot "runner-summary.json"
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

$Evidence = [System.Collections.Generic.List[object]]::new()

function Set-IsolatedProfile {
    param([string]$TestHome)

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
}

function Invoke-GodotEvidence {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$TestHome,
        [switch]$AllowIncomplete
    )

    Set-IsolatedProfile -TestHome $TestHome
    $LogFile = Join-Path $LogRoot "$Name.log"
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan

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
    $MarkerFailure = $Text -cmatch "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:|FATAL:|CRASH:)"
    $Result = "PASS"
    if ($ExitCode -ne 0 -or $MarkerFailure) {
        if ($AllowIncomplete -and -not $MarkerFailure -and $ExitCode -in @(2,3)) {
            $Result = "INCOMPLETE"
        }
        else {
            $Result = "FAIL"
        }
    }

    $Record = [ordered]@{
        name = $Name
        command = "$Godot $($Arguments -join ' ')"
        exit_code = $ExitCode
        result = $Result
        marker_failure = $MarkerFailure
        log = $LogFile
    }
    $Evidence.Add([pscustomobject]$Record)
    return [pscustomobject]$Record
}

function Write-RunnerSummary {
    param(
        [string]$OverallState,
        [string]$GitHead,
        [string]$GodotVersion,
        [object]$ScenarioSummary
    )

    $Payload = [ordered]@{
        schema = "distributed_world_simulator.v0_full_mvp_runner.v1"
        run_id = $RunId
        overall_state = $OverallState
        git_head = $GitHead
        godot_version = $GodotVersion
        final_mode = [bool]$Final
        soak_seconds = $SoakSeconds
        required_final_soak_seconds = $FinalSoakSeconds
        driver = $Driver
        scenario = $ScenarioSummary
        executions = @($Evidence)
    }
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $RunnerSummaryPath
}

$GitHead = ""
$GodotVersion = ""
$OverallState = "FAIL"
$ScenarioSummary = $null
$ExitCode = 1

try {
    $GodotVersion = (& $Godot --version 2>&1 | Out-String).Trim()
    $GitHead = (& git -C $Root rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $GitHead -notmatch "^[0-9a-f]{40}$") {
        throw "Could not determine exact git HEAD for V0 evidence."
    }
    $GodotVersion | Set-Content -Encoding UTF8 (Join-Path $LogRoot "godot-version.txt")
    $GitHead | Set-Content -Encoding UTF8 (Join-Path $LogRoot "git-head.txt")

    $EditorImport = Invoke-GodotEvidence `
        -Name "editor-import" `
        -Arguments @("--headless","--editor","--path",$Root,"--quit") `
        -TestHome (Join-Path $ProfileRoot "editor-import")

    if ($EditorImport.result -eq "FAIL") {
        $OverallState = "FAIL"
        $ExitCode = 1
    }
    else {
        $Prerequisites = @(
            @{ name = "test_v0_full_mvp_harness"; path = "res://tests/runtime/test_v0_full_mvp_harness.gd" },
            @{ name = "test_v0_s1_mvp_launch_options"; path = "res://tests/runtime/test_v0_s1_mvp_launch_options.gd" },
            @{ name = "test_v0_s1_mvp_fixed_tick_movement"; path = "res://tests/runtime/test_v0_s1_mvp_fixed_tick_movement.gd" },
            @{ name = "test_m4_canonical_shared_gameplay_contracts"; path = "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd" },
            @{ name = "test_m7_playable_networked_playground"; path = "res://tests/runtime/test_m7_playable_networked_playground.gd" },
            @{ name = "test_mvp_earth_outpost_authority"; path = "res://tests/runtime/test_mvp_earth_outpost_authority.gd" },
            @{ name = "test_mvp_m3_construction_replication_bridge"; path = "res://tests/runtime/test_mvp_m3_construction_replication_bridge.gd" },
            @{ name = "test_m6_dedicated_recovery_contracts"; path = "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd" },
            @{ name = "test_m7_playable_networked_recovery_processes"; path = "res://tests/runtime/test_m7_playable_networked_recovery_processes.gd" }
        )

        $PrerequisiteFailed = $false
        foreach ($Prerequisite in $Prerequisites) {
            $Record = Invoke-GodotEvidence `
                -Name $Prerequisite.name `
                -Arguments @("--headless","--path",$Root,"--script",$Prerequisite.path) `
                -TestHome (Join-Path $ProfileRoot $Prerequisite.name)
            if ($Record.result -eq "FAIL") {
                $PrerequisiteFailed = $true
            }
        }

        $ScenarioArgs = @(
            "--headless","--path",$Root,
            "--script","res://tools/runtime/v0_full_mvp_scenario.gd","--",
            "--driver=$Driver",
            "--result-file=$ScenarioSummaryPath",
            "--soak-seconds=$SoakSeconds",
            "--integration-head=$GitHead",
            "--run-id=$RunId"
        )
        $ScenarioRecord = Invoke-GodotEvidence `
            -Name "v0-full-mvp-scenario" `
            -Arguments $ScenarioArgs `
            -TestHome (Join-Path $ProfileRoot "v0-full-mvp-scenario") `
            -AllowIncomplete

        if (Test-Path $ScenarioSummaryPath) {
            $ScenarioSummary = Get-Content -Raw $ScenarioSummaryPath | ConvertFrom-Json
        }

        if ($PrerequisiteFailed -or $ScenarioRecord.result -eq "FAIL" -or $null -eq $ScenarioSummary) {
            $OverallState = "FAIL"
            $ExitCode = 1
        }
        else {
            $ScenarioState = [string]$ScenarioSummary.aggregate_state
            switch ($ScenarioState) {
                "PASS" {
                    $OverallState = "PASS"
                    $ExitCode = 0
                }
                "DEPENDENCY_PENDING" {
                    $OverallState = "DEPENDENCY_PENDING"
                    $ExitCode = 2
                }
                "NOT_IMPLEMENTED" {
                    $OverallState = "NOT_IMPLEMENTED"
                    $ExitCode = 3
                }
                default {
                    $OverallState = "FAIL"
                    $ExitCode = 1
                }
            }
        }
    }
}
catch {
    Write-Error $_
    $OverallState = "FAIL"
    $ExitCode = 1
}
finally {
    Write-RunnerSummary `
        -OverallState $OverallState `
        -GitHead $GitHead `
        -GodotVersion $GodotVersion `
        -ScenarioSummary $ScenarioSummary

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
Write-Host "V0 full MVP acceptance aggregate: $OverallState" -ForegroundColor $(
    if ($OverallState -eq "PASS") { "Green" }
    elseif ($OverallState -eq "FAIL") { "Red" }
    else { "Yellow" }
)
Write-Host "Evidence: $LogRoot"
Write-Host "Runner summary: $RunnerSummaryPath"
if (Test-Path $ScenarioSummaryPath) {
    Write-Host "Scenario summary: $ScenarioSummaryPath"
}
exit $ExitCode
