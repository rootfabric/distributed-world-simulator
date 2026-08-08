param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Ch7Runner = Join-Path $Root "RUN_CH7_CHARACTER_EQUIPMENT_TESTS.ps1"
$AssetRoot = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy"
$Garment = Join-Path $AssetRoot "Modular Character Outfits - Fantasy[Standard]\Exports\glTF (Godot-Unreal)\Outfits\Male_Peasant.gltf"

if (-not (Test-Path $Ch7Runner -PathType Leaf)) {
    throw "CH7 acceptance runner is missing: $Ch7Runner"
}
if (-not (Test-Path -LiteralPath $Garment -PathType Leaf)) {
    throw "Male_Peasant.gltf is missing. Run PROBE_CH7_8_QUATERNIUS_OUTFITS.ps1 first."
}

# The Standard pack includes duplicate FBX exports intended for Unity. Their
# relative texture links are noisy in Godot and are not part of CH7.8. Keep the
# authoritative Godot-Unreal glTF export visible and ignore only FBX (Unity).
$FbxDirectories = @(
    Get-ChildItem -LiteralPath $AssetRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "FBX (Unity)" }
)
foreach ($Directory in $FbxDirectories) {
    $IgnorePath = Join-Path $Directory.FullName ".gdignore"
    if (-not (Test-Path -LiteralPath $IgnorePath -PathType Leaf)) {
        Set-Content -LiteralPath $IgnorePath -Value "" -Encoding utf8
    }
}

& $Ch7Runner -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

function Resolve-Godot([string]$Requested) {
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) { $Candidates += $Requested }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }
    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Godot 4.7.1 double was not found. Pass -GodotPath or set GODOT_BIN."
}

function Invoke-Godot-Test([string]$Name, [string]$ScriptPath) {
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan

    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $Output = [System.Collections.Generic.List[string]]::new()
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $Godot @(
            "--headless", "--path", $Root,
            "--script", $ScriptPath
        ) 2>&1 | ForEach-Object {
            $Line = [string]$_
            $Output.Add($Line)
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

    $Text = $Output -join "`n"
    $HasFailureMarker = $Text -match '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
    if ($ExitCode -ne 0 -or $HasFailureMarker) {
        throw "$Name failed with exit code $ExitCode"
    }
}

$Godot = Resolve-Godot $GodotPath
Invoke-Godot-Test "ch7_8_skinned_garment_pose_bridge" "res://tests/characters/test_ch7_8_skinned_garment_pose_bridge.gd"
Invoke-Godot-Test "ch7_8_quaternius_skinned_garment_lab" "res://tests/characters/test_ch7_8_quaternius_skinned_garment_lab.gd"

Write-Host ""
Write-Host "CH7.8 Skinned Garment pose-composition candidate runner: PASS" -ForegroundColor Green
exit 0
