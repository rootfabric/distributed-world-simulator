#requires -Version 7
# Select the exact native double editor; never use 4.7.1 on 4.8 resources.
$ErrorActionPreference = 'Stop'
$project = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'project.godot'
if (-not (Test-Path -LiteralPath $project)) { throw 'DWS_PROJECT_MARKER_MISSING' }
$marker = Get-Content -LiteralPath $project | Where-Object { $_ -match '^config/features=' } | Select-Object -First 1
$migrated = ([string]$marker) -match '"4\.8"'
if ($migrated) {
    $expectedVersion = '4.8.beta1.double.custom_build.4d10419ca'
    $expectedHash = 'f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636'
    $options = @($env:ENGINE48_GODOT_CONSOLE,
        'C:\build-engine48\godot-4.8-beta1\bin\godot.windows.editor.double.x86_64.console.exe',
        'C:\Godot\godot-4.8-beta1-src\bin\godot.windows.editor.double.x86_64.console.exe')
} else {
    $expectedVersion = '4.7.1.stable.double.custom_build.a13da4feb'
    $expectedHash = '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
    $options = @($env:DWS_GODOT_DOUBLE_BIN, 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe')
}
$checked = @()
$chosen = ''
foreach ($candidate in $options) {
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    $checked += "$candidate ($hash)"
    if ($hash -eq $expectedHash) { $chosen = (Resolve-Path -LiteralPath $candidate).Path; break }
}
if (-not $chosen) { throw "DWS_EXACT_GODOT_SHA_NOT_FOUND:expected=$expectedHash;checked=$($checked -join ', ')" }
$nativeOutput = & $chosen --version 2>&1
$versionExit = $LASTEXITCODE
$version = ([string]($nativeOutput | Select-Object -First 1)).Trim()
if ($version -ne $expectedVersion -or ($migrated -and $versionExit -ne 0)) {
    throw "DWS_EXACT_GODOT_VERSION_MISMATCH:$version exit=$versionExit"
}
$env:DWS_GODOT_DOUBLE_BIN = $chosen
if ($migrated) { $env:DWS_ENGINE48_GODOT_SHA256 = $expectedHash } else { Remove-Item Env:DWS_ENGINE48_GODOT_SHA256 -ErrorAction SilentlyContinue }
if ($env:GITHUB_ENV) {
    "DWS_GODOT_DOUBLE_BIN=$chosen" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    if ($migrated) { "DWS_ENGINE48_GODOT_SHA256=$expectedHash" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8 }
}
Write-Host "DWS_EXACT_ENGINE_RESOLVED=$chosen"
Write-Host "DWS_EXACT_ENGINE_VERSION=$version"
Write-Host "DWS_EXACT_ENGINE_SHA256=$expectedHash"
