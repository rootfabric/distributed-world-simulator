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
        & $Godot @("--headless", "--path", $Root, "--script", $ScriptPath) 2>&1 | ForEach-Object {
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
Write-Host "CH9.5: persistent live equipment runtime composition" -ForegroundColor Cyan
Write-Host "Existing ITEM transport, M6 durability and canonical Item Graph remain authoritative." -ForegroundColor Cyan
Write-Host "Character presentation remains derived and movement snapshots remain equipment-free." -ForegroundColor Cyan

Write-Host ""
Write-Host "[editor_import]" -ForegroundColor Cyan
$ImportOutput = & $Godot --headless --editor --path $Root --quit 2>&1
$ImportExit = $LASTEXITCODE
$ImportOutput | ForEach-Object { Write-Host $_ }
$ImportText = $ImportOutput -join "`n"
if ($ImportExit -ne 0 -or $ImportText -match '(?m)(^ERROR:|SCRIPT ERROR:|Parse Error:|Compile Error:)') {
    throw "CH9.5 editor import/parse failed with exit code $ImportExit"
}

Invoke-Godot-Test "ch9_2_inventory_character_composition" "res://tests/characters/test_ch9_2_inventory_character_composition.gd"
Invoke-Godot-Test "ch9_3_replicated_character_presentation" "res://tests/characters/test_ch9_3_replicated_equipment_character_presentation.gd"
Invoke-Godot-Test "ch9_3_real_enet_replication" "res://tests/characters/test_ch9_3_enet_equipment_replication.gd"
Invoke-Godot-Test "ch9_4_equipment_durable_roundtrip" "res://tests/characters/test_ch9_4_equipment_durable_roundtrip.gd"
Invoke-Godot-Test "ch9_4_equipment_checkpoint_reconnect_recovery" "res://tests/characters/test_ch9_4_equipment_reconnect_recovery.gd"
Invoke-Godot-Test "ch9_5_equipment_presentation_coordinator" "res://tests/characters/test_ch9_5_equipment_presentation_coordinator.gd"
Invoke-Godot-Test "ch9_5_persistent_enet_equipment_recovery" "res://tests/characters/test_ch9_5_persistent_enet_equipment_recovery.gd"

Write-Host ""
Write-Host "CH9.5 Live Equipment Runtime Composition candidate runner: PASS" -ForegroundColor Green
exit 0
