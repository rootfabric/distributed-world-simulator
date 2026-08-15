[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Handoffs = 4,

    [switch]$Final,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$AllowDirty,

    [string]$ProjectRoot = "",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$InnerRunner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE_R1.ps1"
if (-not (Test-Path -LiteralPath $InnerRunner -PathType Leaf)) {
    throw "SM0 R1 runner is missing: $InnerRunner"
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)

if ($Stop) {
    & $InnerRunner -Stop -ProjectRoot $ProjectRoot -GodotExe $GodotExe
    exit $LASTEXITCODE
}

$StatusBefore = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) {
    throw "git status failed for $ProjectRoot"
}
if ($StatusBefore.Count -gt 0 -and -not $AllowDirty) {
    throw "SM0 acceptance requires a clean worktree. Current changes:`n$($StatusBefore -join "`n")"
}

$UidBefore = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate pre-existing untracked UID sidecars."
}
$UidBeforeSet = @{}
foreach ($RelativeUid in $UidBefore) {
    $UidBeforeSet[[string]$RelativeUid] = $true
}

$Forward = @{
    Handoffs = $Handoffs
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = $TimeoutSeconds
    AllowDirty = $true
}
if ($Final) { $Forward["Final"] = $true }
if ($Restart) { $Forward["Restart"] = $true }

$InnerExit = 1
try {
    & $InnerRunner @Forward
    $InnerExit = $LASTEXITCODE
}
finally {
    $UidAfter = @(& git -C $ProjectRoot ls-files --others --exclude-standard -- ":(glob)**/*.uid")
    if ($LASTEXITCODE -eq 0) {
        foreach ($RelativeUid in $UidAfter) {
            $RelativeUidText = [string]$RelativeUid
            if (-not $UidBeforeSet.ContainsKey($RelativeUidText)) {
                $GeneratedPath = Join-Path $ProjectRoot $RelativeUidText
                if (Test-Path -LiteralPath $GeneratedPath -PathType Leaf) {
                    Remove-Item -LiteralPath $GeneratedPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[SM0] Removed import-generated UID sidecar: $RelativeUidText"
                }
            }
        }
    }
}

$StatusAfter = @(& git -C $ProjectRoot status --short)
if ($LASTEXITCODE -ne 0) {
    throw "git status failed after SM0 acceptance"
}

$BeforeText = $StatusBefore -join "`n"
$AfterText = $StatusAfter -join "`n"
if ($BeforeText -ne $AfterText) {
    Write-Error "SM0 acceptance changed the source worktree. Before:`n$BeforeText`nAfter:`n$AfterText" -ErrorAction Continue
    exit 1
}

exit $InnerExit
