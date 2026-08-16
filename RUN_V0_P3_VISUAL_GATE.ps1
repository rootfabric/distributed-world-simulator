[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$PreferredPort = 24580,

    [ValidateRange(1, 100)]
    [int]$ProbeCount = 40,

    [string]$GodotExe = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$GodotGuiExe = "",
    [string]$ExpectedP3Ancestor = "f27a60279c8ad61d47ebe3fad81b6898679c660f",

    [switch]$Restart,
    [switch]$SkipProjectPreflight,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AutoLauncher = Join-Path $Root "RUN_V0_MVP_AUTO.ps1"
$ManagedLauncher = Join-Path $Root "RUN_V0_MVP.ps1"

$LocalAppData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
)
if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
    $LocalAppData = $env:TEMP
}
$LauncherRoot = Join-Path $LocalAppData "DistributedWorldSimulator\V0MvpLauncher"
$StatePath = Join-Path $LauncherRoot "session.json"

function Invoke-GitText {
    param([string[]]$Arguments)
    $Output = & git -C $Root @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
    return ([string]($Output -join "`n")).Trim()
}

function Assert-SourceMarker {
    param(
        [string]$RelativePath,
        [string]$Marker,
        [string]$Name
    )
    $Path = Join-Path $Root $RelativePath
    if (-not (Test-Path $Path)) {
        throw "V-P3.1 source gate missing $Name file: $RelativePath"
    }
    if (-not (Select-String -Path $Path -SimpleMatch $Marker -Quiet)) {
        throw "V-P3.1 source gate missing $Name marker '$Marker' in $RelativePath"
    }
}

function Test-ProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -lt 1) {
        return $false
    }
    try {
        Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

if (-not (Test-Path $ManagedLauncher)) {
    throw "V0 managed launcher not found: $ManagedLauncher"
}

if ($Stop) {
    & $ManagedLauncher -Stop
    exit $LASTEXITCODE
}

if (-not (Test-Path $AutoLauncher)) {
    throw "V0 auto launcher not found: $AutoLauncher"
}
if (-not (Test-Path $GodotExe)) {
    throw "Godot console executable not found: $GodotExe"
}

$Head = Invoke-GitText @("rev-parse", "HEAD")
$Branch = Invoke-GitText @("branch", "--show-current")
if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = "DETACHED"
}

$Dirty = & git -C $Root status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect verification checkout state."
}
if (@($Dirty).Count -gt 0) {
    Write-Host "[V-P3.1] Refusing dirty checkout:" -ForegroundColor Red
    & git -C $Root status --short
    throw "V-P3.1 must launch from a clean tracked checkout."
}

& git -C $Root cat-file -e "$ExpectedP3Ancestor^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Expected P3 ancestor is unavailable locally: $ExpectedP3Ancestor"
}
& git -C $Root merge-base --is-ancestor $ExpectedP3Ancestor HEAD 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Current HEAD $Head is not descended from exact R13 P3 ancestor $ExpectedP3Ancestor."
}

$ProtectedRuntimePaths = @(
    "config/resources/v0_resource_nodes.json",
    "scripts/app/earth_p3_resource_mining_app.gd",
    "scripts/runtime/networked_gameplay/p3"
)
& git -C $Root diff --quiet "$ExpectedP3Ancestor..HEAD" -- @ProtectedRuntimePaths
$ProtectedDiffExit = $LASTEXITCODE
if ($ProtectedDiffExit -eq 1) {
    Write-Host "[V-P3.1] Protected P3 runtime differs from frozen R13:" -ForegroundColor Red
    & git -C $Root diff --name-only "$ExpectedP3Ancestor..HEAD" -- @ProtectedRuntimePaths
    throw "Visual validation tooling must not alter the frozen P3 runtime under test."
}
if ($ProtectedDiffExit -ne 0) {
    throw "Unable to compare protected P3 runtime with frozen R13."
}

Assert-SourceMarker `
    -RelativePath "scripts\app\earth_p3_resource_mining_app.gd" `
    -Marker '"checkpoint": "V0-P3-R1"' `
    -Name "Earth P3 application"
Assert-SourceMarker `
    -RelativePath "scripts\runtime\networked_gameplay\p3\resource_mining_target.gd" `
    -Marker '"type": "resource_node"' `
    -Name "resource interaction target"
Assert-SourceMarker `
    -RelativePath "scripts\runtime\networked_gameplay\p3\resource_mining_target.gd" `
    -Marker "_update_depletion_visual" `
    -Name "resource depletion presentation"
Assert-SourceMarker `
    -RelativePath "scripts\runtime\networked_gameplay\p3\resource_mining_service.gd" `
    -Marker '"resource.mine"' `
    -Name "authoritative mining command"

Write-Host "[V-P3.1] Frozen runtime ancestry and source markers: PASS" -ForegroundColor Green
Write-Host "[V-P3.1] Source: $Branch @ $Head"
Write-Host "[V-P3.1] R13 ancestor: $ExpectedP3Ancestor"

$LaunchArguments = @{
    Clients = 2
    PreferredPort = $PreferredPort
    ProbeCount = $ProbeCount
    ServerAddress = "127.0.0.1"
    World = "earth"
    GodotExe = $GodotExe
}
if (-not [string]::IsNullOrWhiteSpace($GodotGuiExe)) {
    $LaunchArguments["GodotGuiExe"] = $GodotGuiExe
}
if ($Restart) {
    $LaunchArguments["Restart"] = $true
}
if ($SkipProjectPreflight) {
    $LaunchArguments["SkipProjectPreflight"] = $true
}

& $AutoLauncher @LaunchArguments
if ($LASTEXITCODE -ne 0) {
    throw "V0 Earth MVP launcher failed before the visual gate became ready."
}

if (-not (Test-Path $StatePath)) {
    throw "Managed V0 session state was not written: $StatePath"
}
try {
    $Session = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
}
catch {
    throw "Managed V0 session state is unreadable: $StatePath"
}

if ([string]$Session.world -ne "earth") {
    throw "V-P3.1 requires world=earth; managed session reports '$($Session.world)'."
}

$ServerPid = [int]$Session.server.pid
if (-not (Test-ProcessAlive $ServerPid)) {
    throw "Dedicated server is not alive after launch (PID $ServerPid)."
}

$Clients = @($Session.clients)
if ($Clients.Count -ne 2) {
    throw "V-P3.1 requires exactly two graphical clients; managed session has $($Clients.Count)."
}

$ExpectedIdentities = @("a", "b")
for ($Index = 0; $Index -lt $ExpectedIdentities.Count; $Index++) {
    $Client = $Clients[$Index]
    $Identity = [string]$Client.identity
    $ClientPid = [int]$Client.pid
    if ($Identity -ne $ExpectedIdentities[$Index]) {
        throw ("Unexpected client identity at index {0}: '{1}'." -f $Index, $Identity)
    }
    if (-not (Test-ProcessAlive $ClientPid)) {
        throw "Graphical client $Identity is not alive after launch (PID $ClientPid)."
    }
}

Write-Host ""
Write-Host "[V-P3.1] READY FOR MANUAL VISUAL CHECK" -ForegroundColor Cyan
Write-Host "[V-P3.1] This launcher does NOT claim PASS automatically. Human observation is required."
Write-Host "[V-P3.1] Log directory: $($Session.log_directory)"
Write-Host "[V-P3.1] Server PID: $ServerPid"
Write-Host "[V-P3.1] Client a PID: $([int]$Clients[0].pid)"
Write-Host "[V-P3.1] Client b PID: $([int]$Clients[1].pid)"
Write-Host ""
Write-Host "Manual checklist:"
Write-Host "  [ ] Both graphical clients are connected to the same Earth session."
Write-Host "  [ ] Client A can see the ore resource node in the playable area."
Write-Host "  [ ] Approach and aim at the ore; the interaction prompt is visible."
Write-Host "  [ ] Press E once; the ore visibly depletes/shrinks and remaining quantity decreases."
Write-Host "  [ ] Exactly one canonical item/ore appears in client A inventory."
Write-Host "  [ ] Client B observes the same depleted resource state."
Write-Host "  [ ] No persistent parser/runtime/network failure is visible in the session logs."
Write-Host ""
Write-Host "Expected first interaction: resource/earth/ore-demo/1, 8 -> 7 units, one item/ore output."
Write-Host "Stop the managed session with: .\RUN_V0_P3_VISUAL_GATE.ps1 -Stop"
Write-Host "Record the human PASS/FAIL against the exact HEAD above before starting P4."
