param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) { $Candidates += $GodotPath }
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }
$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

$Godot = $null
foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
    if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        $Godot = (Resolve-Path -LiteralPath $Candidate).Path
        break
    }
}
if (-not $Godot) {
    throw "Godot 4.7.1 double executable not found. Set GODOT_BIN or pass -GodotPath."
}

$Tests = @(
    [pscustomobject]@{
        Name = "tick-progression-contract"
        Script = "res://tests/persistence/test_authoritative_tick_progression.gd"
        Marker = "Authoritative tick progression: PASS (12 assertions)"
    },
    [pscustomobject]@{
        Name = "m6-dedicated-recovery-processes"
        Script = "res://tests/runtime/test_m6_dedicated_recovery_processes.gd"
        Marker = "M6 dedicated recovery processes: 128 assertions, 0 failures"
    }
)

foreach ($Test in $Tests) {
    Write-Host "M6 tick progression runner: $($Test.Name)"
    $Captured = @()
    & $Godot `
        --headless `
        --path $ProjectRoot `
        --script $Test.Script `
        2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
    $ExitCode = $LASTEXITCODE
    $Output = ($Captured | Out-String)
    if ($ExitCode -ne 0) {
        throw "M6 tick progression test failed: $($Test.Script) exit=$ExitCode"
    }
    if (-not $Output.Contains($Test.Marker)) {
        throw "M6 tick progression marker missing: $($Test.Marker)"
    }
}

Write-Host "M6 tick progression runner: PASS (2/2 suites)" -ForegroundColor Green
