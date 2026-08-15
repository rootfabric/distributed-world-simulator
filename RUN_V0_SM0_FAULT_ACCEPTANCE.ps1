[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Handoffs = 6,

    [switch]$Final,
    [switch]$Restart,
    [switch]$AllowDirty,

    [string]$ProjectRoot = "",

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$FaultProfile = "transport-chaos-v1"
$BaseRunner = Join-Path $PSScriptRoot "RUN_V0_SM0_ACCEPTANCE.ps1"
if (-not (Test-Path -LiteralPath $BaseRunner -PathType Leaf)) {
    throw "SM0 base acceptance runner is missing: $BaseRunner"
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$ExpectedHandoffs = if ($Final) { 20 } else { $Handoffs }

$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$LogsRoot = Join-Path $LocalAppData "DistributedWorldSimulator\SM0Seamless\logs"
$RunStartedAt = Get-Date

$Forward = @{
    Handoffs = $Handoffs
    ProjectRoot = $ProjectRoot
    GodotExe = $GodotExe
    TimeoutSeconds = $TimeoutSeconds
}
if ($Final) { $Forward["Final"] = $true }
if ($Restart) { $Forward["Restart"] = $true }
if ($AllowDirty) { $Forward["AllowDirty"] = $true }

$HadProfile = Test-Path Env:SM0_FAULT_PROFILE
$PreviousProfile = $env:SM0_FAULT_PROFILE
$BaseExit = 1
try {
    $env:SM0_FAULT_PROFILE = $FaultProfile
    Write-Host "[SM0-H1] Running deterministic transport fault profile '$FaultProfile'..."
    & $BaseRunner @Forward
    $BaseExit = $LASTEXITCODE
}
finally {
    if ($HadProfile) { $env:SM0_FAULT_PROFILE = $PreviousProfile }
    else { Remove-Item Env:SM0_FAULT_PROFILE -ErrorAction SilentlyContinue }
}

if ($BaseExit -ne 0) {
    Write-Error "SM0-H1 base acceptance failed under fault profile '$FaultProfile' (exit $BaseExit)." -ErrorAction Continue
    exit $BaseExit
}

if (-not (Test-Path -LiteralPath $LogsRoot -PathType Container)) {
    throw "SM0 log root not found after acceptance: $LogsRoot"
}

$LogDirectory = $null
$Candidates = @(Get-ChildItem -LiteralPath $LogsRoot -Directory | Sort-Object LastWriteTime -Descending)
foreach ($Candidate in $Candidates) {
    if ($Candidate.LastWriteTime -lt $RunStartedAt.AddSeconds(-5)) { continue }
    $ServerAPath = Join-Path $Candidate.FullName "server-a.log"
    $ServerBPath = Join-Path $Candidate.FullName "server-b.log"
    if (-not (Test-Path -LiteralPath $ServerAPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ServerBPath -PathType Leaf)) {
        continue
    }
    $AMarker = Select-String -LiteralPath $ServerAPath -SimpleMatch '"event":"SM0_FAULT_PROFILE_ENABLED"' -Quiet -ErrorAction SilentlyContinue
    $BMarker = Select-String -LiteralPath $ServerBPath -SimpleMatch '"event":"SM0_FAULT_PROFILE_ENABLED"' -Quiet -ErrorAction SilentlyContinue
    if ($AMarker -and $BMarker) {
        $LogDirectory = $Candidate.FullName
        break
    }
}
if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    throw "SM0-H1 could not find fresh logs proving that both authority servers enabled '$FaultProfile'."
}

$Events = New-Object System.Collections.Generic.List[object]
foreach ($Path in @((Join-Path $LogDirectory "server-a.log"), (Join-Path $LogDirectory "server-b.log"))) {
    foreach ($Line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($Line -match '\[SM0_EVENT\]\s+(\{.*\})\s*$') {
            try {
                $Event = $Matches[1] | ConvertFrom-Json
                $Events.Add($Event)
            }
            catch {
                throw "SM0-H1 found an unparseable SM0_EVENT in $Path`: $Line"
            }
        }
    }
}

$ProfileEvents = @($Events | Where-Object {
    $_.event -eq "SM0_FAULT_PROFILE_ENABLED" -and $_.fault_profile -eq $FaultProfile
})
if ($ProfileEvents.Count -ne 2) {
    throw "SM0-H1 expected exactly 2 fault-profile enable events, got $($ProfileEvents.Count)."
}

function Assert-Sm0FaultCount {
    param(
        [string]$EventName,
        [string]$Action,
        [string]$MessageType,
        [int]$Expected
    )
    $Matches = @($Events | Where-Object {
        $_.event -eq $EventName -and
        $_.fault_profile -eq $FaultProfile -and
        $_.fault_action -eq $Action -and
        $_.message_type -eq $MessageType
    })
    if ($Matches.Count -ne $Expected) {
        throw "SM0-H1 expected $Expected $EventName/$Action/$MessageType events, got $($Matches.Count)."
    }
}

Assert-Sm0FaultCount -EventName "SM0_FAULT_INJECTED" -Action "drop" -MessageType "PLAYER_HANDOFF_PREPARE" -Expected $ExpectedHandoffs
Assert-Sm0FaultCount -EventName "SM0_FAULT_INJECTED" -Action "duplicate" -MessageType "PLAYER_HANDOFF_PREPARED" -Expected $ExpectedHandoffs
Assert-Sm0FaultCount -EventName "SM0_FAULT_INJECTED" -Action "delay_reorder" -MessageType "PLAYER_HANDOFF_COMMIT" -Expected $ExpectedHandoffs
Assert-Sm0FaultCount -EventName "SM0_FAULT_INJECTED" -Action "drop" -MessageType "PLAYER_HANDOFF_COMMITTED" -Expected $ExpectedHandoffs
Assert-Sm0FaultCount -EventName "SM0_FAULT_RELEASED" -Action "delay_reorder" -MessageType "PLAYER_HANDOFF_COMMIT" -Expected $ExpectedHandoffs

$SummaryPath = Join-Path $LogDirectory "summary.json"
if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    throw "SM0-H1 summary is missing: $SummaryPath"
}
$Summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
if ($Summary.result -ne "PASS") {
    throw "SM0-H1 base summary is not PASS: $($Summary.result)"
}
if ([int]$Summary.handoffs_completed -ne $ExpectedHandoffs) {
    throw "SM0-H1 summary reports $($Summary.handoffs_completed) handoffs; expected $ExpectedHandoffs."
}
if ([int]$Summary.invariant_violation_count -ne 0) {
    throw "SM0-H1 observed $($Summary.invariant_violation_count) invariant violations."
}

Write-Host ""
Write-Host "SM0-H1 deterministic transport fault analysis: PASS" -ForegroundColor Green
Write-Host "  profile          : $FaultProfile"
Write-Host "  handoffs         : $ExpectedHandoffs / $ExpectedHandoffs"
Write-Host "  drop PREPARE     : $ExpectedHandoffs"
Write-Host "  duplicate PREPARED: $ExpectedHandoffs"
Write-Host "  delay/reorder COMMIT: $ExpectedHandoffs"
Write-Host "  drop COMMITTED   : $ExpectedHandoffs"
Write-Host "  delayed releases : $ExpectedHandoffs"
Write-Host "  logs             : $LogDirectory"
Write-Host "  summary          : $SummaryPath"
exit 0
