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
$Runner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
    throw "SM0 acceptance runner is missing: $Runner"
}

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$LogsRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0Seamless\logs"
$BeforeDirs = @{}
if (Test-Path -LiteralPath $LogsRoot -PathType Container) {
    foreach ($Dir in Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue) {
        $BeforeDirs[$Dir.FullName] = $true
    }
}

$HadP4 = Test-Path Env:SM0_P4_FAST_HANDOFF
$PreviousP4 = $env:SM0_P4_FAST_HANDOFF
$ExitCode = 1
try {
    $env:SM0_P4_FAST_HANDOFF = "1"
    Write-Host "[SM0-P4] Prewarmed fast handoff ENABLED for this run." -ForegroundColor Cyan
    & $Runner @PSBoundParameters
    $ExitCode = $LASTEXITCODE
}
finally {
    if ($HadP4) { $env:SM0_P4_FAST_HANDOFF = $PreviousP4 }
    else { Remove-Item Env:SM0_P4_FAST_HANDOFF -ErrorAction SilentlyContinue }
}

if ($ExitCode -ne 0 -or $Stop) {
    exit $ExitCode
}

$Expected = if ($Final) { 20 } else { $Handoffs }
$NewDirs = @(
    Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction Stop |
        Where-Object { -not $BeforeDirs.ContainsKey($_.FullName) } |
        Sort-Object LastWriteTime -Descending
)
if ($NewDirs.Count -lt 1) {
    throw "SM0-P4 could not locate the new acceptance log directory."
}
$SummaryPath = Join-Path $NewDirs[0].FullName "summary.json"
if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    throw "SM0-P4 acceptance summary is missing: $SummaryPath"
}
$Summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ([string]$Summary.result -ne "PASS") {
    throw "SM0-P4 base acceptance summary is not PASS: $SummaryPath"
}
if ([int]$Summary.handoffs_completed -ne $Expected) {
    throw "SM0-P4 expected $Expected completed handoffs, got $($Summary.handoffs_completed)."
}
if ([int]$Summary.p4_fast_handoffs -ne $Expected) {
    throw "SM0-P4 fast-path evidence incomplete: expected=$Expected actual=$($Summary.p4_fast_handoffs)."
}
if ([int]$Summary.legacy_handoffs -ne 0) {
    throw "SM0-P4 acceptance contained legacy fallback handoffs: $($Summary.legacy_handoffs)."
}

Write-Host ""
Write-Host "SM0-P4 acceptance fast-path evidence: PASS" -ForegroundColor Green
Write-Host "  P4 fast : $($Summary.p4_fast_handoffs) / $Expected"
Write-Host "  legacy  : $($Summary.legacy_handoffs)"
Write-Host "  summary : $SummaryPath"
exit 0
