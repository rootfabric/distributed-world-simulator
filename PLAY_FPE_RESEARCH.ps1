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
if (-not (Test-Path -LiteralPath $Garment -PathType Leaf)) {
    throw "Male_Peasant.gltf is missing. FPE reuses the accepted CH8/CH9 clothing asset."
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

$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$UserArgs = @(
    "--ch8c-upper-inflation=$($UpperInflation.ToString('0.######', $Invariant))",
    "--ch8c-lower-inflation=$($LowerInflation.ToString('0.######', $Invariant))",
    "--ch8c-feet-inflation=$($FeetInflation.ToString('0.######', $Invariant))",
    "--ch8c-inflation-scale=$($InflationScale.ToString('0.######', $Invariant))",
    "--ch9-6-port=$Port"
)
if ($ResetState) {
    $UserArgs += "--ch9-6-reset-state"
}

Write-Host "Godot: $GodotPath"
Write-Host "FPE research - FirstPersonEmbodiment over accepted CH9.6" -ForegroundColor Cyan
Write-Host "C: first/third person | Q: left grab/release | E: right grab/release | 1..0: network hotbar" -ForegroundColor Cyan
Write-Host "Aim at one of the three floating cubes to test local hand grabbing." -ForegroundColor Cyan
Write-Host "Equip Peasant Upper in the inventory to test first-person sleeve synchronization." -ForegroundColor Cyan
Write-Host "Canonical world-item hand grabbing remains fail-closed until a server hand.grab authority contract exists." -ForegroundColor Yellow

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
        "res://scenes/labs/character/quaternius_first_person_embodiment_lab.tscn",
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
