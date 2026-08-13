param(
    [string]$ProfileId = "wrad-arms-cc0",
    [string]$ProfilePath = "",
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

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    if ([string]::IsNullOrWhiteSpace($ProfileId)) {
        throw "Pass -ProfileId or -ProfilePath."
    }
    $ProfileFile = Join-Path $Root ("config\characters\hand-assets\{0}.v1.json" -f $ProfileId)
    if (-not (Test-Path -LiteralPath $ProfileFile)) {
        throw "Hand profile not found: $ProfileFile"
    }
    $ProfilePath = "res://config/characters/hand-assets/$ProfileId.v1.json"
}
if (-not $ProfilePath.StartsWith("res://")) {
    throw "ProfilePath must be a res:// path."
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

Write-Host "Inspecting hand pose calibration: $ProfilePath" -ForegroundColor Cyan
$Run = Invoke-GodotCaptured -Arguments @(
    "--headless",
    "--path", $Root,
    "--script", "res://tests/characters/inspect_fpe_hand_pose_calibration.gd",
    "--",
    "--fpe-hand-profile-path=$ProfilePath"
)
$Text = [string]$Run.OutputText
$Pass = $Text.Contains("FPE hand pose calibration inspector: PASS")
$JsonMarker = $Text.Contains("FPE_HAND_POSE_CALIBRATION_JSON:")
if ([int]$Run.ExitCode -ne 0 -or -not $Pass -or -not $JsonMarker -or $Text.Contains("SCRIPT ERROR:") -or $Text.Contains("Parse Error:") -or $Text.Contains("Compile Error:")) {
    throw "FPE hand pose calibration inspection failed (exit=$($Run.ExitCode), pass_marker=$Pass, json_marker=$JsonMarker)."
}

Write-Host "Hand pose calibration inspection: PASS" -ForegroundColor Green
Write-Host "Copy the FPE_HAND_POSE_CALIBRATION_JSON line back into the chat; it contains inferred native axes and pose rotations for profile tuning." -ForegroundColor Cyan
