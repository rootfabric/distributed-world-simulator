param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Ch6Runner = Join-Path $Root "RUN_CH6_CONTROLLABLE_PRESENTATION_TESTS.ps1"
if (-not (Test-Path $Ch6Runner)) {
    throw "CH6 acceptance runner is missing: $Ch6Runner"
}

& $Ch6Runner -GodotPath $GodotPath
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
    $Output = @()
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        $Output = & $Godot @(
            "--headless", "--path", $Root,
            "--script", $ScriptPath
        ) 2>&1
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

$Godot = Resolve-Godot $GodotPath
Invoke-Godot-Test "ch7_character_equipment_domain" "res://tests/characters/test_ch7_character_equipment_domain.gd"
Invoke-Godot-Test "ch7_character_equipment_presenter" "res://tests/characters/test_ch7_character_equipment_presenter.gd"

Write-Host ""
Write-Host "CH7 Universal Character Equipment CH7.0-CH7.3 runner: PASS" -ForegroundColor Green
exit 0
