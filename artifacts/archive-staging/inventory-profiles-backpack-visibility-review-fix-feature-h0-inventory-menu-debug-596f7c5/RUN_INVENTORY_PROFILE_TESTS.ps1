param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
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
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Checks = @(
    [ordered]@{ Name = "editor-import"; Arguments = @("--headless", "--editor", "--path", $ProjectRoot, "--quit") },
    [ordered]@{ Name = "profiles"; Arguments = @("--headless", "--path", $ProjectRoot, "--script", "res://tests/ui/test_inventory_interaction_profiles.gd") },
    [ordered]@{ Name = "stack-transfers"; Arguments = @("--headless", "--path", $ProjectRoot, "--script", "res://tests/items/test_item_stack_transfers.gd") },
    [ordered]@{ Name = "ui-i0"; Arguments = @("--headless", "--path", $ProjectRoot, "--script", "res://tests/ui/test_inventory_ui_i0_architecture.gd") },
    [ordered]@{ Name = "ui-i1"; Arguments = @("--headless", "--path", $ProjectRoot, "--script", "res://tests/ui/test_inventory_ui_i1_interactions.gd") },
    [ordered]@{ Name = "ui-i2"; Arguments = @("--headless", "--path", $ProjectRoot, "--script", "res://tests/ui/test_inventory_ui_i2_large_storage.gd") }
)

foreach ($Check in $Checks) {
    Write-Host ""
    Write-Host "[$($Check.Name)]" -ForegroundColor Cyan
    $Output = & $Godot @($Check.Arguments) 2>&1
    $ExitCode = $LASTEXITCODE
    $Output | Tee-Object -FilePath (Join-Path $ReportDirectory "inventory-profiles-$($Check.Name).log") | ForEach-Object { Write-Host $_ }
    $OutputText = $Output | Out-String
    if ($ExitCode -ne 0 -or $OutputText -match '(?m): FAIL(?:\s|\()') {
        throw "$($Check.Name) failed with exit code $ExitCode"
    }
}

Write-Host ""
Write-Host "Inventory interaction profile tests: PASS" -ForegroundColor Green
