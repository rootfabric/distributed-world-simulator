#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Test,
    [string]$GodotBin = $env:DWS_GODOT_DOUBLE_BIN,
    [string]$ResumePath = '',
    [string]$ExpectedSha256 = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $GodotBin = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "GODOT_NOT_FOUND: $GodotBin"
}
$GodotBin = (Resolve-Path -LiteralPath $GodotBin).Path
$Expected = '3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5'
$Actual = (Get-FileHash -LiteralPath $GodotBin -Algorithm SHA256).Hash
if ($Actual -ne $Expected) { throw "GODOT_SHA256_MISMATCH: $Actual" }
$Version = ((& $GodotBin --version 2>&1) | Out-String).Trim()
if ($Version -ne '4.7.1.stable.double.custom_build.a13da4feb') {
    throw "GODOT_VERSION_MISMATCH: $Version"
}
Write-Host "GODOT_PATH=$GodotBin"
Write-Host "GODOT_VERSION=$Version"
Write-Host "GODOT_SHA256=$Actual"
if ($Test) {
    if ($ResumePath -or $ExpectedSha256) { throw 'TEST_AND_RESUME_ARE_SEPARATE_OPERATIONS' }
    & python (Join-Path $Root 'validation/ecology/evo_arch2_a11/run_exact.py') --godot $GodotBin
    if ($LASTEXITCODE -ne 0) { throw "A11_EXACT_FAILED: $LASTEXITCODE" }
    return
}
if ([string]::IsNullOrWhiteSpace($ResumePath) -ne [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    throw 'RESUME_REQUIRES_PATH_AND_EXTERNAL_SHA256'
}
$Logs = Join-Path $Root 'artifacts/runtime/eco-a11-launch'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-ffff'
& $GodotBin --headless --editor --path $Root --import 2>&1 |
    Tee-Object -FilePath (Join-Path $Logs "$Stamp-import.log")
if ($LASTEXITCODE -ne 0) { throw "GODOT_IMPORT_FAILED: $LASTEXITCODE" }
$LaunchArguments = @('--path', $Root, '--log-file', (Join-Path $Logs "$Stamp-habitat.log"),
    'res://scenes/ecology/habitat/persistent_habitat.tscn')
if ($ResumePath) {
    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'INVALID_EXTERNAL_SHA256' }
    $LaunchArguments += @('--', "--eco-habitat-save=$ResumePath", "--eco-habitat-sha=$ExpectedSha256")
}
& $GodotBin @LaunchArguments
if ($LASTEXITCODE -ne 0) { throw "HABITAT_EXIT: $LASTEXITCODE" }
