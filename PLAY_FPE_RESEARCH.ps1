param(
    [string]$GodotPath = "",
    [int]$Port = 39965,
    [switch]$ResetState,
    [string]$HandVisualScene = "",
    [string]$SkinnedHandScene = "",
    [double]$UpperInflation = 0.032,
    [double]$LowerInflation = 0.042,
    [double]$FeetInflation = 0.040,
    [double]$InflationScale = 1.25
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Garment = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy\Modular Character Outfits - Fantasy[Standard]\Exports\glTF (Godot-Unreal)\Outfits\Male_Peasant.gltf"

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
if ($Port -lt 1024 -or $Port -gt 65535) {
    throw "Port must be in range 1024..65535."
}
if (-not [string]::IsNullOrWhiteSpace($HandVisualScene) -and -not $HandVisualScene.StartsWith("res://")) {
    throw "HandVisualScene must be a Godot res:// PackedScene path."
}
if (-not [string]::IsNullOrWhiteSpace($SkinnedHandScene) -and -not $SkinnedHandScene.StartsWith("res://")) {
    throw "SkinnedHandScene must be a Godot res:// PackedScene path."
}
if (-not [string]::IsNullOrWhiteSpace($HandVisualScene) -and -not [string]::IsNullOrWhiteSpace($SkinnedHandScene)) {
    throw "Choose either -HandVisualScene (S7 BoneAttachment path) or -SkinnedHandScene (S8 weighted Skin path), not both."
}

foreach ($Pair in @(
    @{ Name = "UpperInflation"; Value = $UpperInflation },
    @{ Name = "LowerInflation"; Value = $LowerInflation },
    @{ Name = "FeetInflation"; Value = $FeetInflation }
)) {
    if ($Pair.Value -lt 0.0 -or $Pair.Value -gt 0.080) {
        throw "$($Pair.Name) must be in range 0.000..0.080 metres."
    }
}
if ($InflationScale -lt 0.10 -or $InflationScale -gt 2.00) {
    throw "InflationScale must be in range 0.10..2.00."
}

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

$FatalMarkers = @(
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "ERROR: Failed to load script"
)

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
    throw "Godot class-cache preflight failed (exit=$($Preflight.ExitCode), fatal_marker=$PreflightFatal). Run RUN_FPE_RESEARCH_TESTS.ps1 for the captured diagnostics."
}
Write-Host "Godot class-cache preflight: PASS" -ForegroundColor Green

Write-Host "Validating FPE graphical composition" -ForegroundColor Cyan
$SceneGate = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--path", $Root,
    "--script", "res://tests/characters/test_first_person_embodiment_lab_load.gd"
)
$SceneGateFatal = Get-FatalGodotMarker -OutputText ([string]$SceneGate.OutputText)
$SceneGatePass = ([string]$SceneGate.OutputText).Contains("FirstPersonEmbodiment graphical scene load: PASS")
if ([int]$SceneGate.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($SceneGateFatal) -or -not $SceneGatePass) {
    throw "FPE graphical composition preflight failed (exit=$($SceneGate.ExitCode), fatal_marker=$SceneGateFatal, pass_marker=$SceneGatePass). Run RUN_FPE_RESEARCH_TESTS.ps1 before PLAY."
}
Write-Host "FPE graphical composition preflight: PASS" -ForegroundColor Green

$GarmentAvailable = Test-Path -LiteralPath $Garment -PathType Leaf
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$UserArgs = @("--ch9-6-port=$Port")
if ($GarmentAvailable) {
    $UserArgs = @(
        "--ch8c-upper-inflation=$($UpperInflation.ToString('0.######', $Invariant))",
        "--ch8c-lower-inflation=$($LowerInflation.ToString('0.######', $Invariant))",
        "--ch8c-feet-inflation=$($FeetInflation.ToString('0.######', $Invariant))",
        "--ch8c-inflation-scale=$($InflationScale.ToString('0.######', $Invariant))",
        "--ch9-6-port=$Port"
    )
}
if ($ResetState) {
    $UserArgs += "--ch9-6-reset-state"
}
if (-not [string]::IsNullOrWhiteSpace($HandVisualScene)) {
    $UserArgs += "--fpe-hand-visual-scene=$HandVisualScene"
}
if (-not [string]::IsNullOrWhiteSpace($SkinnedHandScene)) {
    $UserArgs += "--fpe-skinned-hand-scene=$SkinnedHandScene"
}

Write-Host "Godot: $GodotPath"
Write-Host "FPE research - R2 S8 skinned first-person hand retargeting over accepted CH9.6" -ForegroundColor Cyan
Write-Host "C: first/third person | Q: left grab/release | E: right grab/release | 1..0: instant local hotbar selection" -ForegroundColor Cyan
Write-Host "Fix8 hotbar rule: slot selection sends NO Item Graph command and requests NO durable checkpoint; concrete item actions remain server-authoritative." -ForegroundColor Cyan
Write-Host "R2 S2-S7 are retained: item/grip catalogs, articulated poses, two-hand first/third-person support, substitutable visuals and the PackedScene BoneAttachment adapter remain available." -ForegroundColor Cyan
Write-Host "R2 S8 adds a weighted ArrayMesh + Skin route. Source named skin binds are validated and retargeted to the canonical 17-bone hand skeleton; index-only skins fail closed." -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($SkinnedHandScene)) {
    Write-Host "S8 runtime mode: weighted skinned resource requested: $SkinnedHandScene" -ForegroundColor Cyan
    Write-Host "HUD should report S8 skinned hand: REQUESTED and L/R:RESOURCE_SKINNED_RETARGETED." -ForegroundColor Cyan
} elseif (-not [string]::IsNullOrWhiteSpace($HandVisualScene)) {
    Write-Host "S8 runtime mode: legacy S7 BoneAttachment resource requested: $HandVisualScene" -ForegroundColor Cyan
    Write-Host "HUD should retain S7 REQUESTED and S8 DEFAULT." -ForegroundColor Cyan
} else {
    Write-Host "S8 runtime mode: no hand resource requested; procedural S6 provider remains active." -ForegroundColor Cyan
    Write-Host "Weighted demo: rerun with -SkinnedHandScene 'res://tests/fixtures/fpe_s8_skinned_hand_visual.tscn'." -ForegroundColor Cyan
}
Write-Host "Switch 1 -> 2 -> empty while moving. Beacon pinch, mount-base two-hand support, S5 world-left support, empty release and zero-stall movement must remain unchanged." -ForegroundColor Cyan
Write-Host "S8 proves real weighted skin binding and named-bone retargeting. The fixture is still contract geometry, not final hand art; arbitrary incompatible rest spaces remain fail-closed." -ForegroundColor Cyan
Write-Host "Aim at one of the three floating cubes to test local hand grabbing when the left first-person hand is free." -ForegroundColor Cyan
if ($GarmentAvailable) {
    Write-Host "Quaternius Male_Peasant asset found: real clothing + first-person sleeve path enabled." -ForegroundColor Cyan
    Write-Host "Equip Peasant Upper in the inventory to test first-person sleeve synchronization." -ForegroundColor Cyan
} else {
    Write-Host "WARNING: Male_Peasant.gltf is not present in this checkout." -ForegroundColor Yellow
    Write-Host "The FPE lab will still launch. Clothing viewmodel will use procedural sleeves and CH8C real-garment presentation may report MALE_PEASANT_SCENE_MISSING." -ForegroundColor Yellow
}
Write-Host "Canonical world-item hand grabbing remains fail-closed until a server hand.grab authority contract exists." -ForegroundColor Yellow

$GodotArgs = @(
    "--path", $Root,
    "res://scenes/labs/character/quaternius_first_person_embodiment_lab.tscn",
    "--"
) + $UserArgs
$Run = Invoke-GodotCaptured -Arguments $GodotArgs
exit [int]$Run.ExitCode