param(
    [string]$GodotBin = $env:GODOT_BIN,
    [string]$Python = "python",
    [string]$OutputPath = ""
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot not found: $GodotBin" }
$Output = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path $Root ("artifacts\mvp4-graphical-" + [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")) } else { $OutputPath }
if (Test-Path -LiteralPath $Output) { throw "Refusing to overwrite evidence: $Output" }
$PreviousUtf8 = $env:PYTHONUTF8
try {
    $env:PYTHONUTF8 = "1"
    & $Python (Join-Path $Root "tests\integration\test_v0_mvp_4_visible_graphical_shared_dig.py") --engine $GodotBin --output $Output
    if ($LASTEXITCODE -ne 0) { throw "MVP4 shared dig failed; inspect $Output\manifest.json and visible-acceptance.json" }
}
finally {
    if ($null -eq $PreviousUtf8) { Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue }
    else { $env:PYTHONUTF8 = $PreviousUtf8 }
}
Write-Host "Automatic MVP4 shared dig and visible terrain checks passed. This was NOT manual input or independent predicate acceptance. Evidence: $Output"
