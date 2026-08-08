param(
    [string]$GodotPath = ""
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
    throw "Male_Peasant.gltf is missing. Run PROBE_CH7_8_QUATERNIUS_OUTFITS.ps1 first."
}

Write-Host "Godot: $GodotPath"
Write-Host "CH7.8 garment: $Garment"
Write-Host "Controls: O outfit | H helmet | B backpack | C FP/TP | Ctrl crouch | Space jump" -ForegroundColor Cyan

$PreviousErrorActionPreference = $ErrorActionPreference
$NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
$PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
$ExitCode = 1
try {
    $ErrorActionPreference = "Continue"
    if ($null -ne $NativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
    }
    & $GodotPath --path $Root "res://scenes/labs/character/quaternius_skinned_garment_lab.tscn" 2>&1 |
        ForEach-Object { Write-Host $_ }
    $ExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($null -ne $NativePreference) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
    }
}
exit $ExitCode
