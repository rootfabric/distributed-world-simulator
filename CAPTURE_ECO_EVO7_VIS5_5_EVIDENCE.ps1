param(
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$OutputDir = ""
)
$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Expected = "4.7.1.stable.double.custom_build.a13da4feb"
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RootDir "artifacts\eco_vis5_5_visual_evidence"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot binary not found: $GodotPath" }
$Actual = (& $GodotPath --version | Select-Object -First 1).Trim()
if ($Actual -ne $Expected) { throw "Expected canonical double Godot '$Expected', got '$Actual'" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$PreviousOut = $env:DWS_VIS55_EVIDENCE_DIR
try {
    $env:DWS_VIS55_EVIDENCE_DIR = (Resolve-Path -LiteralPath $OutputDir).Path
    & $GodotPath --rendering-method gl_compatibility --resolution 1280x720 --path $RootDir --script "res://tests/ecology/eco_evo7_vis5_5_capture_evidence.gd"
    if ($LASTEXITCODE -ne 0) { throw "VIS5.5 graphical capture failed with exit code $LASTEXITCODE" }
}
finally {
    if ($null -eq $PreviousOut) { Remove-Item Env:\DWS_VIS55_EVIDENCE_DIR -ErrorAction SilentlyContinue } else { $env:DWS_VIS55_EVIDENCE_DIR = $PreviousOut }
}
Write-Host "VIS5.5 evidence: $OutputDir"
