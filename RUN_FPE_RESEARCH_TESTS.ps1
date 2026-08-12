param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        $env:GODOT_BIN,
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            $GodotPath = (Resolve-Path $Candidate).Path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path $GodotPath)) {
    throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}

$FatalMarkers = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "ERROR: Failed to load script"
)

function Invoke-GodotCaptured {
    param([string[]]$Arguments)

    $OutputLines = [System.Collections.Generic.List[string]]::new()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $GodotPath @Arguments 2>&1 | ForEach-Object {
            $Line = [string]$_
            $OutputLines.Add($Line)
            Write-Host $Line
        }
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }

    return @{
        ExitCode = $ExitCode
        OutputText = ($OutputLines -join "`n")
    }
}

function Get-FatalGodotMarker {
    param([string]$OutputText)
    foreach ($Marker in $FatalMarkers) {
        if ($OutputText.Contains($Marker)) {
            return $Marker
        }
    }
    return ""
}

Write-Host "Refreshing Godot global script class cache" -ForegroundColor Cyan
$Preflight = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--editor",
    "--path", $Root,
    "--quit"
)
$PreflightFatal = Get-FatalGodotMarker -OutputText ([string]$Preflight.OutputText)
if ([int]$Preflight.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($PreflightFatal)) {
    Write-Host "FAIL: Godot class-cache preflight (exit=$($Preflight.ExitCode), fatal_marker=$PreflightFatal)" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Godot class-cache preflight" -ForegroundColor Green

$Tests = @(
    @{ Path = "res://tests/characters/test_first_person_embodiment_contract.gd"; PassMarker = "FirstPersonEmbodiment contract: PASS" },
    @{ Path = "res://tests/characters/test_first_person_hotbar_network_adapter.gd"; PassMarker = "FirstPerson hotbar nonblocking adapter: PASS" },
    @{ Path = "res://tests/characters/test_first_person_hotbar_presentation_prediction.gd"; PassMarker = "FirstPerson hotbar presentation prediction: PASS" },
    @{ Path = "res://tests/characters/test_first_person_hotbar_local_selection.gd"; PassMarker = "FirstPerson hotbar local selection: PASS" },
    @{ Path = "res://tests/characters/test_first_person_equipment_result_policy.gd"; PassMarker = "FirstPerson equipment result policy: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_shared_held_item_state.gd"; PassMarker = "FPE R2 shared held-item state: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_third_person_held_item_presenter.gd"; PassMarker = "FPE R2 third-person held-item presenter: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s2_item_viewmodel_catalog.gd"; PassMarker = "FPE R2 S2 item viewmodel catalog: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s2_profiled_presenters.gd"; PassMarker = "FPE R2 S2 profiled presenters: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s3_hand_pose_catalog.gd"; PassMarker = "FPE R2 S3 hand pose catalog: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s3_articulated_hand_rig.gd"; PassMarker = "FPE R2 S3 articulated hand rig: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s3_posed_viewmodel.gd"; PassMarker = "FPE R2 S3 posed viewmodel: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s4_two_hand_grip_contract.gd"; PassMarker = "FPE R2 S4 two-hand grip contract: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s4_two_hand_viewmodel.gd"; PassMarker = "FPE R2 S4 two-hand viewmodel: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s5_secondary_hand_support.gd"; PassMarker = "FPE R2 S5 secondary-hand support: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s5_two_hand_third_person_presenter.gd"; PassMarker = "FPE R2 S5 two-hand third-person presenter: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s6_hand_visual_provider_boundary.gd"; PassMarker = "FPE R2 S6 hand visual provider boundary: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s7_resource_backed_hand_visual_provider.gd"; PassMarker = "FPE R2 S7 resource-backed hand visual provider: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s8_skinned_hand_retarget_provider.gd"; PassMarker = "FPE R2 S8 skinned hand retarget provider: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s8_skinned_configurable_viewmodel.gd"; PassMarker = "FPE R2 S8 skinned configurable viewmodel: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s9_volumetric_skinned_hand_asset.gd"; PassMarker = "FPE R2 S9 volumetric skinned hand asset: PASS" },
    @{ Path = "res://tests/characters/test_fpe_r2_s10_hand_asset_profiles.gd"; PassMarker = "FPE R2 S10 portable hand asset profiles: PASS" },
    @{ Path = "res://tests/characters/test_fpe_sandbox_owner_collision_isolation.gd"; PassMarker = "FPE sandbox owner collision isolation: PASS" },
    @{ Path = "res://tests/characters/test_first_person_embodiment_performance_gate.gd"; PassMarker = "FirstPersonEmbodiment performance gate: PASS" },
    @{ Path = "res://tests/characters/test_first_person_embodiment_lab_load.gd"; PassMarker = "FirstPersonEmbodiment graphical scene load: PASS" }
)

foreach ($Test in $Tests) {
    $TestPath = [string]$Test.Path
    Write-Host "Running $TestPath" -ForegroundColor Cyan
    $Run = Invoke-GodotCaptured -Arguments @(
        "--headless",
        "--path", $Root,
        "--script", $TestPath
    )
    $EngineFatal = Get-FatalGodotMarker -OutputText ([string]$Run.OutputText)
    $PassMarkerSeen = ([string]$Run.OutputText).Contains([string]$Test.PassMarker)

    if ([int]$Run.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($EngineFatal) -or -not $PassMarkerSeen) {
        Write-Host "FAIL: $TestPath (exit=$($Run.ExitCode), fatal_marker=$EngineFatal, pass_marker=$PassMarkerSeen)" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS: $TestPath" -ForegroundColor Green
}

Write-Host "FirstPersonEmbodiment focused tests: PASS" -ForegroundColor Green
exit 0
