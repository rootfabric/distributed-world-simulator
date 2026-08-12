param(
    [string]$GodotPath = "",
    [int]$Port = 39965,
    [switch]$ResetState,
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
    param(
        [string[]]$Arguments
    )

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
    param(
        [string]$OutputText
    )
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
$UserArgs = @(
    "--ch9-6-port=$Port"
)
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

Write-Host "Godot: $GodotPath"
Write-Host "FPE research - R2 S4 two-hand grip presentation over accepted CH9.6" -ForegroundColor Cyan
Write-Host "C: first/third person | Q: left grab/release | E: right grab/release | 1..0: instant local hotbar selection" -ForegroundColor Cyan
Write-Host "Fix8 hotbar rule: slot selection sends NO Item Graph command and requests NO durable checkpoint; concrete item actions remain server-authoritative." -ForegroundColor Cyan
Write-Host "R2 S2/S3: selected ItemDefinition resolves visual/grip profiles and articulated finger poses." -ForegroundColor Cyan
Write-Host "R2 S4 gate: sandbox slot 1 beacon remains one-hand; slot 2 mount-base is the bounded two-hand demonstration item. Selecting slot 2 must move the LEFT articulated hand onto the item's secondary support anchor while the RIGHT remains primary." -ForegroundColor Cyan
Write-Host "Switch 1 -> 2 -> 1 -> empty while moving. Slot 2 must engage both hands; slot 1/empty must release the left hand back to its normal OPEN pose with no frame stall." -ForegroundColor Cyan
Write-Host "Q is intentionally reserved while the left hand is acting as the secondary support hand. This is presentation-only reservation, not gameplay authority." -ForegroundColor Cyan
Write-Host "Third-person still shows the existing right-hand world proxy; third-person two-arm IK is NOT claimed by S4 and remains a later animation task." -ForegroundColor Cyan
Write-Host "Aim at one of the three floating cubes to test local hand grabbing when the left hand is free." -ForegroundColor Cyan
Write-Host "S4 Fix1 physics gate: while Q/E holds a local sandbox RigidBody, it must NOT push or self-move the CharacterBody3D. Owner/body collision is mutually excluded only during hold and a 200 ms release grace; world collision layers/masks stay unchanged." -ForegroundColor Cyan
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
