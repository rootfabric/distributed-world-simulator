[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$PreferredPort = 24580,
    [ValidateRange(1, 100)]
    [int]$ProbeCount = 40,
    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "",
    [string]$ExpectedP3Repair = "ef3ad5f0afc433802d639171d938e4720b3a46ec",
    [switch]$Restart,
    [switch]$SkipProjectPreflight,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AutoLauncher = Join-Path $Root "RUN_V0_MVP_AUTO.ps1"
$ManagedLauncher = Join-Path $Root "RUN_V0_MVP.ps1"
$LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) { $LocalAppData = $env:TEMP }
$StatePath = Join-Path $LocalAppData "DistributedWorldSimulator\V0MvpLauncher\session.json"

function Invoke-GitText {
    param([string[]]$Arguments)
    $Output = & git -C $Root @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
    return ([string]($Output -join "`n")).Trim()
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -lt 1) { return $false }
    try { Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

if (-not (Test-Path $ManagedLauncher)) { throw "V0 managed launcher not found: $ManagedLauncher" }
if ($Stop) { & $ManagedLauncher -Stop; exit $LASTEXITCODE }
if (-not (Test-Path $AutoLauncher)) { throw "V0 auto launcher not found: $AutoLauncher" }
if (-not (Test-Path $GodotExe)) { throw "Godot console executable not found: $GodotExe" }

$Head = Invoke-GitText @("rev-parse", "HEAD")
$Branch = Invoke-GitText @("branch", "--show-current")
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "DETACHED" }
$Dirty = & git -C $Root status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect validation checkout state." }
if (@($Dirty).Count -gt 0) {
    & git -C $Root status --short
    throw "V-P3.1 R2 must launch from a clean tracked checkout."
}

& git -C $Root cat-file -e "$ExpectedP3Repair^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { throw "Expected P3 visual repair is unavailable locally: $ExpectedP3Repair" }
& git -C $Root merge-base --is-ancestor $ExpectedP3Repair HEAD 2>$null
if ($LASTEXITCODE -ne 0) { throw "Current HEAD $Head is not descended from exact P3 visual repair $ExpectedP3Repair." }

$ProtectedRuntimePaths = @(
    "config/resources/v0_resource_nodes.json",
    "scripts/app/earth_p3_resource_mining_app.gd",
    "scripts/runtime/networked_gameplay/p3"
)
& git -C $Root diff --quiet "$ExpectedP3Repair..HEAD" -- @ProtectedRuntimePaths
$ProtectedDiffExit = $LASTEXITCODE
if ($ProtectedDiffExit -eq 1) {
    & git -C $Root diff --name-only "$ExpectedP3Repair..HEAD" -- @ProtectedRuntimePaths
    throw "V-P3.1 R2 tooling must not alter the repaired P3 runtime under test."
}
if ($ProtectedDiffExit -ne 0) { throw "Unable to compare repaired P3 runtime boundary." }

$P3App = Join-Path $Root "scripts\app\earth_p3_resource_mining_app.gd"
foreach ($Marker in @(
    '"checkpoint": "V0-P3-R1"',
    'P3_RESOURCE_FOCUS_PRIORITY_BONUS',
    '_p3_interaction_focus_score'
)) {
    if (-not (Select-String -Path $P3App -SimpleMatch $Marker -Quiet)) {
        throw "V-P3.1 R2 repaired presentation marker missing: $Marker"
    }
}
$MiningService = Join-Path $Root "scripts\runtime\networked_gameplay\p3\resource_mining_service.gd"
if (-not (Select-String -Path $MiningService -SimpleMatch '"resource.mine"' -Quiet)) {
    throw "V-P3.1 R2 authoritative resource.mine marker missing."
}

Write-Host "[V-P3.1 R2] Repaired runtime ancestry/source gate: PASS" -ForegroundColor Green
Write-Host "[V-P3.1 R2] Source: $Branch @ $Head"
Write-Host "[V-P3.1 R2] Visual repair: $ExpectedP3Repair"

$LaunchArguments = @{
    Clients = 2
    PreferredPort = $PreferredPort
    ProbeCount = $ProbeCount
    ServerAddress = "127.0.0.1"
    World = "earth"
    GodotExe = $GodotExe
}
if (-not [string]::IsNullOrWhiteSpace($GodotGuiExe)) { $LaunchArguments["GodotGuiExe"] = $GodotGuiExe }
if ($Restart) { $LaunchArguments["Restart"] = $true }
if ($SkipProjectPreflight) { $LaunchArguments["SkipProjectPreflight"] = $true }

& $AutoLauncher @LaunchArguments
if ($LASTEXITCODE -ne 0) { throw "V0 Earth MVP launcher failed before V-P3.1 R2 became ready." }
if (-not (Test-Path $StatePath)) { throw "Managed V0 session state was not written: $StatePath" }
try { $Session = Get-Content -Path $StatePath -Raw | ConvertFrom-Json }
catch { throw "Managed V0 session state is unreadable: $StatePath" }

if ([string]$Session.world -ne "earth") { throw "V-P3.1 R2 requires world=earth." }
$ServerPid = [int]$Session.server.pid
if (-not (Test-ProcessAlive $ServerPid)) { throw "Dedicated server is not alive after launch (PID $ServerPid)." }
$Clients = @($Session.clients)
if ($Clients.Count -ne 2) { throw "V-P3.1 R2 requires exactly two graphical clients; got $($Clients.Count)." }
$ExpectedIdentities = @("a", "b")
for ($Index = 0; $Index -lt $ExpectedIdentities.Count; $Index++) {
    $Identity = [string]$Clients[$Index].identity
    $ClientPid = [int]$Clients[$Index].pid
    if ($Identity -ne $ExpectedIdentities[$Index]) {
        throw ("Unexpected client identity at index {0}: '{1}'." -f $Index, $Identity)
    }
    if (-not (Test-ProcessAlive $ClientPid)) { throw "Graphical client $Identity is not alive (PID $ClientPid)." }
}

Write-Host ""
Write-Host "[V-P3.1 R2] READY FOR REPAIRED MINING CHECK" -ForegroundColor Cyan
Write-Host "[V-P3.1 R2] Log directory: $($Session.log_directory)"
Write-Host "[V-P3.1 R2] Server PID: $ServerPid; client a: $([int]$Clients[0].pid); client b: $([int]$Clients[1].pid)"
Write-Host ""
Write-Host "Manual mining checklist:"
Write-Host "  [ ] Approach the nearby resource ore on client A until within 5 m."
Write-Host "  [ ] Aim at it: prompt must be 'E — Добыть руду · Руда ×8' (not 'Подобрать: Руда')."
Write-Host "  [ ] Press E once: resource state changes 8 -> 7 and target visibly shrinks."
Write-Host "  [ ] Exactly one canonical item/ore appears through the existing inventory UI."
Write-Host "  [ ] Client B observes the same depleted state."
Write-Host "  [ ] Record any MULTIPLAYER_SAME_REVISION_MUTATION separately; do not hide it."
Write-Host ""
Write-Host "Stop with: .\RUN_V0_P3_VISUAL_GATE.ps1 -Stop"
Write-Host "This launcher does not self-claim V-P3.1/P3/V0 acceptance."
