param(
    [string]$GodotPath = "",
    [int]$Port = 39965,
    [string]$EvidencePath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Launcher = Join-Path $Root "PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1"
$FocusedTest = "res://tests/characters/test_ch9_6_playable_network_equipment_ui.gd"
$Garment = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy\Modular Character Outfits - Fantasy[Standard]\Exports\glTF (Godot-Unreal)\Outfits\Male_Peasant.gltf"
$BaseRoot = Join-Path $Root "assets\external\quaternius\base_characters"
$AnimationRoot = Join-Path $Root "assets\external\quaternius\animation_library"
$PowerShellExe = if ($PSVersionTable.PSEdition -eq "Core") { Join-Path $PSHOME "pwsh.exe" } else { Join-Path $PSHOME "powershell.exe" }

function Get-SceneAssetCount([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return 0 }
    return @(
        Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".glb", ".gltf", ".fbx") }
    ).Count
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string]$Question)
    while ($true) {
        $Answer = (Read-Host "$Question [y/n]").Trim().ToLowerInvariant()
        if ($Answer -in @("y", "yes")) { return $true }
        if ($Answer -in @("n", "no")) { return $false }
        Write-Host "Enter y or n." -ForegroundColor Yellow
    }
}

function Invoke-GodotCaptured {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $Output = @()
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false }
        $Output = & $GodotPath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) { Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference }
    }
    return [ordered]@{
        exit_code = [int]$ExitCode
        output = @($Output | ForEach-Object { [string]$_ })
        text = (@($Output | ForEach-Object { [string]$_ }) -join "`n")
    }
}

if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) { throw "CH9.6 launcher not found: $Launcher" }
if (-not (Test-Path -LiteralPath $PowerShellExe -PathType Leaf)) { throw "PowerShell executable not found: $PowerShellExe" }
if ($Port -lt 1024 -or $Port -gt 65535) { throw "Port must be in range 1024..65535." }

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    foreach ($Candidate in @(
        $env:GODOT_BIN,
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
            $GodotPath = (Resolve-Path -LiteralPath $Candidate).Path
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found. Expected C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe or pass a valid -GodotPath."
}
if (-not (Test-Path -LiteralPath $Garment -PathType Leaf)) {
    throw "CH9.6 Modular Character Outfits asset is missing: $Garment"
}
$BaseSceneCount = Get-SceneAssetCount $BaseRoot
$AnimationSceneCount = Get-SceneAssetCount $AnimationRoot
if ($BaseSceneCount -lt 1) {
    throw "CH9.6 real Quaternius base character assets are missing under: $BaseRoot`nRun .\INSTALL_CH4_QUATERNIUS_ASSETS.ps1 after placing the Quaternius Standard ZIPs in Downloads."
}
if ($AnimationSceneCount -lt 1) {
    throw "CH9.6 Quaternius animation assets are missing under: $AnimationRoot`nRun .\INSTALL_CH4_QUATERNIUS_ASSETS.ps1 after placing the Quaternius Standard ZIPs in Downloads."
}

Write-Host "Godot preflight: PASS -> $GodotPath" -ForegroundColor Green
Write-Host "Quaternius base character preflight: PASS ($BaseSceneCount scene files)" -ForegroundColor Green
Write-Host "Quaternius animation preflight: PASS ($AnimationSceneCount scene files)" -ForegroundColor Green
Write-Host "Quaternius modular outfit preflight: PASS" -ForegroundColor Green
Write-Host ""
Write-Host "Running Godot editor import/parse preflight..." -ForegroundColor Cyan
$Import = Invoke-GodotCaptured -Arguments @("--headless", "--editor", "--path", $Root, "--quit")
$Import.output | ForEach-Object { Write-Host $_ }
$ImportFatalSyntax = $Import.text -match '(?m)(SCRIPT ERROR:|Parse Error:|Compile Error:)'
if ($Import.exit_code -ne 0 -or $ImportFatalSyntax) {
    throw "CH9.6 editor import/parse preflight failed with exit code $($Import.exit_code). Graphical acceptance was not started."
}
$KnownFbxImportErrors = @($Import.output | Where-Object {
    $_ -match '(?i)ERROR:|WARNING:' -and (
        $_ -match '(?i)FBX|Texture2D|T_(Ranger|Peasant|Regular_)' -or
        $_ -match '(?i)assets/external/quaternius/modular_outfits_fantasy/.*/FBX \(Unity\)/'
    )
}).Count
if ($KnownFbxImportErrors -gt 0) {
    Write-Host "Godot editor import completed with exit code 0; unrelated Quaternius FBX/Unity import diagnostics were observed ($KnownFbxImportErrors lines)." -ForegroundColor Yellow
    Write-Host "They are not used by CH9.6; the focused CH9.6 runtime probe below is authoritative for the required glTF path." -ForegroundColor Yellow
}
Write-Host "Godot editor import/parse preflight: PASS" -ForegroundColor Green

Write-Host ""
Write-Host "Running focused CH9.6 runtime/presentation preflight..." -ForegroundColor Cyan
$Focused = Invoke-GodotCaptured -Arguments @("--headless", "--path", $Root, "--script", $FocusedTest)
$Focused.output | ForEach-Object { Write-Host $_ }
$FocusedPassMarker = $Focused.text -match 'CH9\.6 playable network equipment UI: PASS \([0-9]+ assertions\)'
if ($Focused.exit_code -ne 0 -or -not $FocusedPassMarker) {
    throw "CH9.6 focused runtime/presentation preflight failed with exit code $($Focused.exit_code). Graphical acceptance was not started."
}
Write-Host "Focused CH9.6 runtime/presentation preflight: PASS" -ForegroundColor Green

if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidenceDir = Join-Path $Root "artifacts\ch9-6-manual"
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
    $EvidencePath = Join-Path $EvidenceDir ("ch9-6-graphical-acceptance-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
} elseif (-not [System.IO.Path]::IsPathRooted($EvidencePath)) {
    $EvidencePath = Join-Path $Root $EvidencePath
}
$EvidenceDirectory = Split-Path -Parent $EvidencePath
if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) { New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null }

function Invoke-Ch96Lab {
    param([switch]$ResetState)
    $ChildArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Launcher,
        "-Port", [string]$Port, "-GodotPath", $GodotPath
    )
    if ($ResetState) { $ChildArgs += "-ResetState" }
    Write-Host "Launching graphical CH9.6 client..." -ForegroundColor Cyan
    & $PowerShellExe @ChildArgs
    return [int]$LASTEXITCODE
}

$Head = "UNKNOWN"
try {
    $HeadCandidate = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($HeadCandidate) { $Head = $HeadCandidate.Trim() }
} catch { $Head = "UNKNOWN" }

Write-Host ""
Write-Host "CH9.6 MANUAL GRAPHICAL ACCEPTANCE" -ForegroundColor Cyan
Write-Host "Repository head: $Head" -ForegroundColor Cyan
Write-Host "This runner never infers graphical PASS; it records only explicit operator observations." -ForegroundColor Yellow
Write-Host ""
Write-Host "PASS 1 / RESET STATE" -ForegroundColor Cyan
Write-Host "1. Wait for HUD status READY and the Inventory UI to open."
Write-Host "2. Drag lower/upper/feet wearables from backpack into equipment slots."
Write-Host "3. Confirm clothing appears on the real Quaternius character."
Write-Host "4. Press Tab and verify walking, jump and crouch."
Write-Host "5. Close the application normally."

$FirstExit = Invoke-Ch96Lab -ResetState
if ($FirstExit -ne 0) { throw "CH9.6 first graphical launch failed (exit code $FirstExit). No graphical PASS can be recorded." }

$FirstReady = Read-YesNo "Did the lab reach READY with the Inventory UI available?"
$FirstPresentation = Read-YesNo "Did equipped clothing appear correctly on the real Quaternius character?"
$FirstMovement = Read-YesNo "Did walking, jump and crouch remain functional while equipped?"
$FirstNormalClose = Read-YesNo "Did you close the first run normally after the checks?"

Write-Host ""
Write-Host "PASS 2 / RECOVERY" -ForegroundColor Cyan
Write-Host "1. Do not equip anything manually at startup."
Write-Host "2. Confirm equipment slots and Quaternius presentation restore automatically."
Write-Host "3. Drag one restored equipped item back to backpack."
Write-Host "4. Confirm that exact wearable disappears from the character."
Write-Host "5. Close the application normally."

$SecondExit = Invoke-Ch96Lab
if ($SecondExit -ne 0) { throw "CH9.6 recovery graphical launch failed (exit code $SecondExit). No graphical PASS can be recorded." }

$Recovered = Read-YesNo "Were the previously equipped items restored automatically after restart?"
$RecoveredPresentation = Read-YesNo "Was recovered equipment already visible on the Quaternius character without a new drag?"
$UnequipPresentation = Read-YesNo "After dragging a restored item back to backpack, did its visual disappear?"

$AllObservations = @($FirstReady,$FirstPresentation,$FirstMovement,$FirstNormalClose,$Recovered,$RecoveredPresentation,$UnequipPresentation)
$ObservationPass = -not ($AllObservations -contains $false)
$ProcessPass = ($FirstExit -eq 0 -and $SecondExit -eq 0)
$Decision = if ($ObservationPass -and $ProcessPass) { "OPERATOR_REPORTED_PASS" } else { "OPERATOR_REPORTED_FAIL" }

$Evidence = [ordered]@{
    schema = "planet_simulator.ch9_6_manual_graphical_acceptance_evidence.v1"
    stage = "CH9.6 Playable Network Equipment Lab"
    branch = "feature/ch9-6-playable-network-equipment-lab"
    tested_head = $Head
    recorded_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    launcher = "PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1"
    operator_runner = "ACCEPT_CH9_6_GRAPHICAL.ps1"
    import_preflight = "PASS"
    focused_runtime_preflight = "PASS"
    ignored_unrelated_fbx_diagnostic_lines = $KnownFbxImportErrors
    assets = [ordered]@{ base_scene_count = $BaseSceneCount; animation_scene_count = $AnimationSceneCount; modular_outfit = $Garment }
    first_launch = [ordered]@{ reset_state = $true; exit_code = $FirstExit }
    second_launch = [ordered]@{ reset_state = $false; exit_code = $SecondExit }
    observations = [ordered]@{
        ready_and_inventory_available = $FirstReady
        equipped_quaternius_presentation_visible = $FirstPresentation
        movement_jump_crouch_functional = $FirstMovement
        first_run_closed_normally = $FirstNormalClose
        equipment_restored_after_restart = $Recovered
        recovered_quaternius_presentation_visible_without_new_drag = $RecoveredPresentation
        unequipped_visual_removed = $UnequipPresentation
    }
    process_pass = $ProcessPass
    observation_pass = $ObservationPass
    decision = $Decision
}
$Evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

Write-Host ""
Write-Host "Evidence: $EvidencePath" -ForegroundColor Cyan
if ($Decision -eq "OPERATOR_REPORTED_PASS") {
    Write-Host "CH9.6 manual graphical acceptance: OPERATOR REPORTED PASS" -ForegroundColor Green
    exit 0
}
Write-Host "CH9.6 manual graphical acceptance: OPERATOR REPORTED FAIL" -ForegroundColor Red
exit 2
