param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$Arguments)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan
    & $Godot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
    Write-Host "${Name}: PASS" -ForegroundColor Green
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
Write-Host "Godot: $Godot"
Write-Host "Project: $ProjectRoot"

Invoke-GodotCheck -Name "Project import and script parse" -Arguments @(
    "--headless", "--editor", "--path", $ProjectRoot, "--quit"
)

$Tests = @(
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/network/test_network_contracts.gd",
    "res://tests/network/test_loopback_command_transport.gd",
    "res://tests/entities/test_authority_revision_semantics.gd"
)
foreach ($Test in $Tests) {
    Invoke-GodotCheck -Name ([IO.Path]::GetFileNameWithoutExtension($Test)) -Arguments @(
        "--headless", "--path", $ProjectRoot, "--script", $Test
    )
}
Write-Host ""
Write-Host "Foundation/N0 part 1 contract tests passed." -ForegroundColor Green
