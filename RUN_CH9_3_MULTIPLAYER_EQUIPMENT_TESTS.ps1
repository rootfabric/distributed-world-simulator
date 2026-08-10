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
Write-Host "CH9.3: server-authoritative equipment over the existing Item Graph replication channel" -ForegroundColor Cyan
Write-Host "Movement snapshots remain equipment-free; no mesh or rig dependency is added to the server." -ForegroundColor Cyan

Write-Host ""
Write-Host "[editor_import]" -ForegroundColor Cyan
$ImportOutput = & $Godot --headless --editor --path $Root --quit 2>&1
$ImportExit = $LASTEXITCODE
$ImportOutput | ForEach-Object { Write-Host $_ }
$ImportText = $ImportOutput -join "`n"
if ($ImportExit -ne 0 -or $ImportText -match '(?m)(^ERROR:|SCRIPT ERROR:|Parse Error:|Compile Error:)') {
    throw "CH9.3 editor import/parse failed with exit code $ImportExit"
}

Invoke-Godot-Test "ch9_0_item_graph_equipment_source" "res://tests/characters/test_ch9_item_graph_equipment_source.gd"
Invoke-Godot-Test "ch9_1_authoritative_equipment_operations" "res://tests/characters/test_ch9_1_authoritative_equipment_operations.gd"
Invoke-Godot-Test "ch9_2_inventory_character_composition" "res://tests/characters/test_ch9_2_inventory_character_composition.gd"
Invoke-Godot-Test "ch9_3_equipment_item_command_contract" "res://tests/characters/test_ch9_3_equipment_item_command_contract.gd"
Invoke-Godot-Test "ch9_3_multiplayer_equipment_authority" "res://tests/characters/test_ch9_3_multiplayer_equipment_authority.gd"
Invoke-Godot-Test "ch9_3_multiplayer_equipment_replica_projection" "res://tests/characters/test_ch9_3_multiplayer_equipment_replica_projection.gd"
Invoke-Godot-Test "ch9_3_replicated_equipment_character_presentation" "res://tests/characters/test_ch9_3_replicated_equipment_character_presentation.gd"
Invoke-Godot-Test "ch9_3_enet_equipment_replication" "res://tests/characters/test_ch9_3_enet_equipment_replication.gd"

Write-Host ""
Write-Host "CH9.3 Multiplayer Equipment Presentation candidate runner: PASS" -ForegroundColor Green
exit 0
