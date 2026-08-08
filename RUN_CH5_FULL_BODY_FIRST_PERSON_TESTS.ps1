param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

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

$Godot = Resolve-Godot $GodotPath
$OriginalRequire = $env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS
$BaseRoot = Join-Path $Root "assets/external/quaternius/base_characters"
$AnimationRoot = Join-Path $Root "assets/external/quaternius/animation_library"
$HasBase = (Test-Path $BaseRoot) -and @(
    Get-ChildItem -Path $BaseRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".glb", ".gltf", ".fbx") }
).Count -gt 0
$HasAnimations = (Test-Path $AnimationRoot) -and @(
    Get-ChildItem -Path $AnimationRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".glb", ".gltf", ".fbx") }
).Count -gt 0
$env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS = if ($HasBase -and $HasAnimations) { "1" } else { "0" }

function Invoke-Godot([string]$Name, [string[]]$Arguments) {
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $Output = @()
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        $Output = & $Godot @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }
    $Output | ForEach-Object { Write-Host $_ }
    $Text = $Output -join "`n"
    $HasFailureMarker = $Text -match '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
    if ($ExitCode -ne 0 -or $HasFailureMarker) {
        throw "$Name failed with exit code $ExitCode"
    }
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Quaternius external assets required: $($env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS)"

    Invoke-Godot "asset_preflight" @(
        "--headless", "--path", $Root,
        "--script", "res://scripts/characters/importing/quaternius_asset_preflight.gd"
    )
    Invoke-Godot "editor_import" @("--headless", "--editor", "--path", $Root, "--quit")

    Invoke-Godot "ch4_avatar_presenter_regression" @(
        "--headless", "--path", $Root,
        "--script", "res://tests/characters/test_ch4_quaternius_avatar_presenter.gd"
    )
    Invoke-Godot "ch4_character_lab_regression" @(
        "--headless", "--path", $Root,
        "--script", "res://tests/characters/test_ch4_quaternius_character_lab.gd"
    )
    Invoke-Godot "ch5_first_person_adapter" @(
        "--headless", "--path", $Root,
        "--script", "res://tests/characters/test_ch5_full_body_first_person_adapter.gd"
    )
    Invoke-Godot "ch5_first_person_lab" @(
        "--headless", "--path", $Root,
        "--script", "res://tests/characters/test_ch5_full_body_first_person_lab.gd"
    )

    Write-Host ""
    Write-Host "CH5 full-body first-person tests: PASS" -ForegroundColor Green
}
finally {
    if ($null -eq $OriginalRequire) {
        Remove-Item Env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS -ErrorAction SilentlyContinue
    }
    else {
        $env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS = $OriginalRequire
    }
}
