param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$Python = "python",
    [switch]$RuntimeOnly
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Pinned Godot executable not found: $GodotBin" }
$Output = Join-Path $Root "artifacts\mvp2-exact"
if (Test-Path -LiteralPath $Output) { throw "Preserve or move previous evidence first: $Output" }
$PreviousUtf8 = $env:PYTHONUTF8
Push-Location $Root
try {
    $env:PYTHONUTF8 = "1"
    $Arguments = @("docs/control/mvp-act0-r1/validate_mvp2.py", "--engine", $GodotBin)
    if ($RuntimeOnly) { $Arguments += "--runtime-only" }
    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) { throw "MVP2 verification failed; see $Output\result.json and raw logs" }
}
finally {
    Pop-Location
    if ($null -eq $PreviousUtf8) { Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue }
    else { $env:PYTHONUTF8 = $PreviousUtf8 }
}
Write-Host "MVP2 machine workload passed. Independent review and predicate closure are NOT performed by this runner."
