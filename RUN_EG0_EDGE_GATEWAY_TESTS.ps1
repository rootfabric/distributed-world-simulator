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

    if ($env:HOME) {
        $Candidates += (Join-Path $env:HOME ".local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64")
    }

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
$Tests = @(
    "res://tests/network/test_eg0_edge_gateway_contracts.gd",
    "res://tests/network/test_eg0_edge_gateway_fixtures.gd",
    "res://tests/network/test_eg0_world_graph_contracts.gd",
    "res://tests/network/test_eg0_cwip_connect_gate_contracts.gd",
    "res://tests/network/test_eg0_r6_review_repairs.gd",
    "res://tests/network/test_eg0_r7_review_repairs.gd"
)

$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $Godot --headless --editor --path $ProjectRoot --quit
    if ($LASTEXITCODE -ne 0) { throw "Godot editor parse failed with exit code $LASTEXITCODE" }

    foreach ($Test in $Tests) {
        Write-Host "[$Test]" -ForegroundColor Cyan
        & $Godot --headless --path $ProjectRoot --script $Test
        if ($LASTEXITCODE -ne 0) { throw "$Test failed with exit code $LASTEXITCODE" }
    }
}
finally {
    if ($null -eq $previous) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $previous
    }
}

Write-Host "EG0 Edge Gateway focused suite: PASS" -ForegroundColor Green
