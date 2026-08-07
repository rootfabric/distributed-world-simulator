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
    $Output = & $Godot @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $Output | ForEach-Object { Write-Host $_ }
    $Text = $Output -join "`n"
    if ($ExitCode -ne 0 -or $Text -match "(: FAIL|SCRIPT ERROR:|Parse Error:|Compile Error:)") {
        throw "$Name failed with exit code $ExitCode"
    }
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Quaternius external assets required: $($env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS)"
    Invoke-Godot "editor_import" @("--headless", "--editor", "--path", $Root, "--quit")
    Invoke-Godot "avatar_presenter" @("--headless", "--path", $Root, "--script", "res://tests/characters/test_ch4_quaternius_avatar_presenter.gd")
    Invoke-Godot "character_lab" @("--headless", "--path", $Root, "--script", "res://tests/characters/test_ch4_quaternius_character_lab.gd")
    Write-Host ""
    Write-Host "CH4 Quaternius character tests: PASS" -ForegroundColor Green
}
finally {
    if ($null -eq $OriginalRequire) {
        Remove-Item Env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS -ErrorAction SilentlyContinue
    }
    else {
        $env:PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS = $OriginalRequire
    }
}
