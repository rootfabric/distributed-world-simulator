param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Ch78Runner = Join-Path $Root "RUN_CH7_8_SKINNED_GARMENT_TESTS.ps1"

if (-not (Test-Path $Ch78Runner -PathType Leaf)) {
    throw "Accepted CH7.8 runner is missing: $Ch78Runner"
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
    $HasFailureMarker = $Text -match '(?m)(^ERROR:|: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
    if ($ExitCode -ne 0 -or $HasFailureMarker) {
        throw "$Name failed with exit code $ExitCode"
    }
}

$Godot = Resolve-Godot $GodotPath
Write-Host "Godot: $Godot"

& $Ch78Runner -GodotPath $Godot
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Invoke-Godot-Test "ch8_layered_equipment_contract" "res://tests/characters/test_ch8_layered_equipment_contract.gd"
Invoke-Godot-Test "ch8_layered_equipment_presentation_diff" "res://tests/characters/test_ch8_layered_equipment_presentation_diff.gd"
Invoke-Godot-Test "ch8b_quaternius_selective_skinned_parts" "res://tests/characters/test_ch8b_quaternius_selective_skinned_parts.gd"
Invoke-Godot-Test "ch8b_real_layered_equipment_presentation" "res://tests/characters/test_ch8b_real_layered_equipment_presentation.gd"
Invoke-Godot-Test "ch8c_quaternius_topology_occlusion" "res://tests/characters/test_ch8c_quaternius_topology_occlusion.gd"
Invoke-Godot-Test "ch8c_quaternius_layered_equipment_lab" "res://tests/characters/test_ch8c_quaternius_layered_equipment_lab.gd"

Write-Host ""
Write-Host "CH8 Layered Equipment + topology-aware open-garment occlusion candidate runner: PASS" -ForegroundColor Green
exit 0
