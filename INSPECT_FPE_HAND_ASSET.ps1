param(
    [Parameter(Mandatory=$true)][string]$Scene,
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        $env:GODOT_BIN,
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            $GodotPath = (Resolve-Path $Candidate).Path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path $GodotPath)) {
    throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}
if ([string]::IsNullOrWhiteSpace($Scene) -or -not $Scene.StartsWith("res://")) {
    throw "Scene must be a Godot res:// path to an imported GLB/GLTF/FBX/tscn PackedScene."
}

function Invoke-GodotCaptured {
    param([string[]]$Arguments)
    $OutputLines = [System.Collections.Generic.List[string]]::new()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    $ExitCode = 1
    try {
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $GodotPath @Arguments 2>&1 | ForEach-Object {
            $Line = [string]$_
            $OutputLines.Add($Line)
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
    return @{
        ExitCode = $ExitCode
        OutputText = ($OutputLines -join "`n")
    }
}

Write-Host "Importing pending Godot resources before hand asset inspection" -ForegroundColor Cyan
# --import waits for pending resource imports to finish, unlike --editor --quit,
# which may exit after the filesystem scan while a freshly copied external GLB
# still has no ResourceLoader-visible imported scene.
$Preflight = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--path", $Root,
    "--import"
)
$PreflightText = [string]$Preflight.OutputText
if ([int]$Preflight.ExitCode -ne 0 -or $PreflightText.Contains("SCRIPT ERROR:") -or $PreflightText.Contains("Parse Error:") -or $PreflightText.Contains("Compile Error:")) {
    throw "Godot import preflight failed before hand asset inspection (exit=$($Preflight.ExitCode))."
}

Write-Host "Inspecting hand asset: $Scene" -ForegroundColor Cyan
$Run = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--path", $Root,
    "--script", "res://tests/characters/inspect_fpe_hand_asset.gd",
    "--",
    "--fpe-inspect-hand-scene=$Scene"
)
$Pass = ([string]$Run.OutputText).Contains("FPE hand asset inspector: PASS")
if ([int]$Run.ExitCode -ne 0 -or -not $Pass) {
    throw "FPE hand asset inspection failed (exit=$($Run.ExitCode), pass_marker=$Pass)."
}

Write-Host "Hand asset inspection: PASS" -ForegroundColor Green
Write-Host "Copy the FPE_HAND_ASSET_INSPECTION_JSON line back into the chat; it contains mesh paths, skeletons and Skin bind names needed to finish a portable profile." -ForegroundColor Cyan
