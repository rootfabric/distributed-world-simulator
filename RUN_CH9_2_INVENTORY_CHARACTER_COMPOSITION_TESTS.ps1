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

function Assert-PowerShell-Parse([string]$Path, [string]$Name) {
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name file is missing: $Path"
    }
    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$ParseErrors
    ) | Out-Null
    if ($null -ne $ParseErrors -and $ParseErrors.Count -gt 0) {
        foreach ($ParseError in $ParseErrors) {
            Write-Host ("PowerShell parse error: {0} at {1}" -f $ParseError.Message, $ParseError.Extent.Text) -ForegroundColor Red
        }
        throw "$Name failed PowerShell parser validation"
    }
    Write-Host "$Name: PASS" -ForegroundColor Green
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
Write-Host "CH9.2: real Inventory UI + canonical equipment container + CH8 character presentation" -ForegroundColor Cyan
Write-Host "Network equipment mutation remains disabled until CH9.3" -ForegroundColor Cyan

Assert-PowerShell-Parse (Join-Path $Root "PLAY_CH9_2_INVENTORY_CHARACTER_LAB.ps1") "graphical_launcher_parse"

Write-Host ""
Write-Host "[editor_import]" -ForegroundColor Cyan
& $Godot --headless --editor --path $Root --quit
if ($LASTEXITCODE -ne 0) { throw "CH9.2 editor import/parse failed with exit code $LASTEXITCODE" }

Invoke-Godot-Test "ch8_layered_equipment_contract" "res://tests/characters/test_ch8_layered_equipment_contract.gd"
Invoke-Godot-Test "ch9_item_graph_equipment_source" "res://tests/characters/test_ch9_item_graph_equipment_source.gd"
Invoke-Godot-Test "ch9_1_authoritative_equipment_operations" "res://tests/characters/test_ch9_1_authoritative_equipment_operations.gd"
Invoke-Godot-Test "ch9_1_multi_conflict_guard" "res://tests/characters/test_ch9_1_multi_conflict_guard.gd"
Invoke-Godot-Test "ch9_2_inventory_character_composition" "res://tests/characters/test_ch9_2_inventory_character_composition.gd"
Invoke-Godot-Test "ch9_2_inventory_ui_equipment_routes" "res://tests/characters/test_ch9_2_inventory_ui_equipment_routes.gd"

Write-Host ""
Write-Host "CH9.2 Inventory + Character Composition candidate runner: PASS" -ForegroundColor Green
exit 0
