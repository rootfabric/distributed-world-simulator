[CmdletBinding()]
param(
    [ValidateRange(2, 12)][int]$Handoffs = 2,
    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,
    [string]$ProjectRoot = "",
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [ValidateRange(60, 900)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$SourceRunner = Join-Path $ProjectRoot "RUN_V0_SM0_REPEATED_ACTIVATION_OUTAGE_ACCEPTANCE.ps1"
if (-not (Test-Path -LiteralPath $SourceRunner -PathType Leaf)) {
    throw "SM0-H4.1 source runner not found: $SourceRunner"
}

# PowerShell engine workaround:
# @($list) can throw 'Argument types do not match' for List[object] created by New-Object.
# Keep the H4.1 runner logic byte-for-byte identical except for constructing that one list
# through its .NET constructor, which avoids the binder defect.
$Original = Get-Content -LiteralPath $SourceRunner -Raw -ErrorAction Stop
$Needle = '$Cycles = New-Object System.Collections.Generic.List[object]'
$Replacement = '$Cycles = [System.Collections.Generic.List[object]]::new()'
$Matches = ([regex]::Matches($Original, [regex]::Escape($Needle))).Count
if ($Matches -ne 1) {
    throw "SM0-H4.1 FIX1 expected exactly one generic-list construction to replace, found $Matches."
}
$Patched = $Original.Replace($Needle, $Replacement)
if ($Patched -eq $Original) {
    throw "SM0-H4.1 FIX1 replacement produced no change."
}
if (([regex]::Matches($Patched, [regex]::Escape($Needle))).Count -ne 0) {
    throw "SM0-H4.1 FIX1 left the vulnerable construction in the patched runner."
}
if (([regex]::Matches($Patched, [regex]::Escape($Replacement))).Count -ne 1) {
    throw "SM0-H4.1 FIX1 did not produce exactly one constructor-based list."
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) "distributed-world-simulator-sm0-h41-fix1"
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$TempRunner = Join-Path $TempRoot ("RUN_V0_SM0_REPEATED_ACTIVATION_OUTAGE_ACCEPTANCE_FIX1_{0}_{1}.ps1" -f $PID, ([Guid]::NewGuid().ToString("N")))
$Patched | Set-Content -LiteralPath $TempRunner -Encoding UTF8

$Invoke = @{
    Handoffs = $Handoffs
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = $TimeoutSeconds
}
if ($Final) { $Invoke.Final = $true }
if ($Stop) { $Invoke.Stop = $true }
if ($Restart) { $Invoke.Restart = $true }
if ($AllowDirty) { $Invoke.AllowDirty = $true }

try {
    Write-Host "[SM0-H4.1-FIX1] Applying PowerShell List[object] constructor workaround to temporary runner only."
    & $TempRunner @Invoke
    $Code = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $TempRunner -Force -ErrorAction SilentlyContinue
}

exit $Code
