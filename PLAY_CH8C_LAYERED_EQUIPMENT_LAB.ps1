param(
    [string]$GodotPath = "",
    [double]$UpperInflation = 0.032,
    [double]$LowerInflation = 0.038,
    [double]$FeetInflation = 0.036,
    [double]$InflationScale = 1.0
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
if (-not (Test-Path -LiteralPath $Garment -PathType Leaf)) {
    throw "Male_Peasant.gltf is missing. Run PROBE_CH8_QUATERNIUS_LAYERED_PARTS.ps1 first."
}

foreach ($Pair in @(
    @{Name="UpperInflation"; Value=$UpperInflation},
    @{Name="LowerInflation"; Value=$LowerInflation},
    @{Name="FeetInflation"; Value=$FeetInflation}
)) {
    if ($Pair.Value -lt 0.0 -or $Pair.Value -gt 0.080) {
        throw "$($Pair.Name) must be in range 0.000..0.080 metres."
    }
}
if ($InflationScale -lt 0.10 -or $InflationScale -gt 2.00) {
    throw "InflationScale must be in range 0.10..2.00."
}

$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$UpperText = $UpperInflation.ToString("0.######", $Invariant)
$LowerText = $LowerInflation.ToString("0.######", $Invariant)
$FeetText = $FeetInflation.ToString("0.######", $Invariant)
$ScaleText = $InflationScale.ToString("0.######", $Invariant)

$UserArgs = @(
    "--ch8c-upper-inflation=$UpperText",
    "--ch8c-lower-inflation=$LowerText",
    "--ch8c-feet-inflation=$FeetText",
    "--ch8c-inflation-scale=$ScaleText"
)

Write-Host "Godot: $GodotPath"
Write-Host "CH8C layered garment source: $Garment"
Write-Host "Fit: BODY_VISIBLE_INFLATED_OVERLAY" -ForegroundColor Cyan
Write-Host "Inflation target max (m): upper=$UpperText lower=$LowerText feet=$FeetText scale=$ScaleText" -ForegroundColor Cyan
Write-Host "Controls: U upper | L lower | K feet | H helmet | B backpack | C FP/TP | Ctrl crouch | Space jump" -ForegroundColor Cyan

$PreviousErrorActionPreference = $ErrorActionPreference
$NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
$PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
$ExitCode = 1
try {
    $ErrorActionPreference = "Continue"
    if ($null -ne $NativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
    }
    $GodotArgs = @(
        "--path", $Root,
        "res://scenes/labs/character/quaternius_layered_equipment_lab.tscn",
        "--"
    ) + $UserArgs
    & $GodotPath @GodotArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($null -ne $NativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
    }
}
exit $ExitCode
