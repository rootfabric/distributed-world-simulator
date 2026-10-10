[CmdletBinding()]
param(
    [string] $GodotConsole = '',
    [string] $AssetSource = '',
    [int] $Port = 24580,
    [string] $Slot = 'char2-avatar-smoke',
    [ValidateRange(30,900)][int] $StartupTimeoutSeconds = 240,
    [switch] $SkipImport
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CHAR1-Common.ps1')
$package = Get-CHAR1Root
$project = Join-Path $package 'project'
$identity = Assert-CHAR1Snapshot $package
$godot = Resolve-CHAR1Godot $GodotConsole
[void](Ensure-CHAR1RealAssets $package $AssetSource)

if ($Port -lt 1024 -or $Port -gt 65535) { throw 'CHAR2_INVALID_PORT' }
if ($Slot -notmatch '^[a-z0-9][a-z0-9_-]{0,47}$') { throw 'CHAR2_INVALID_SLOT' }
$existing = @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    throw ("CHAR2_PORT_ALREADY_BOUND:{0}; do not kill existing server" -f $Port)
}
if (-not $SkipImport) {
    [void](Invoke-CHAR1Command $godot.Console $project @('--headless','--editor','--import','--quit') 'char2-two-client-import')
}

$evidence = Join-Path $package 'evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$quoted = '"{0}"' -f $project

# Use exactly the validated UX0 Host/Join argument contract; no duplicated
# authority or new network protocol. Server is the sole gameplay-state owner.
$serverArgs = @(
    '--headless','--path',$quoted,'--',
    '--role=dedicated-server','--network-mvp','--product-seam',
    '--world=earth','--server-address=127.0.0.1',
    ('--server-port={0}' -f $Port),('--instance-id={0}' -f $Slot),
    ('--node-id=char2-server-{0}' -f $Slot)
)
$owned = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$launchSucceeded = $false
try {
$server = Start-Process -FilePath $godot.Console -ArgumentList $serverArgs -WorkingDirectory $project -RedirectStandardOutput (Join-Path $evidence 'char2-server.stdout.log') -RedirectStandardError (Join-Path $evidence 'char2-server.stderr.log') -PassThru
$null = $server.Handle
$owned.Add($server)

$bound = $false
$runtimeReady = $false
$watch = [System.Diagnostics.Stopwatch]::StartNew()
while ($watch.Elapsed.TotalSeconds -lt $StartupTimeoutSeconds) {
    Start-Sleep -Milliseconds 250
    $server.Refresh()
    if ($server.HasExited) {
        throw ("CHAR2_SERVER_EXITED_BEFORE_READY:{0}; inspect evidence/char2-server*.log" -f $server.ExitCode)
    }
    $listeners = @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
    $bound = @($listeners | Where-Object { $_.OwningProcess -eq $server.Id }).Count -gt 0
    if (@($listeners | Where-Object { $_.OwningProcess -ne $server.Id }).Count -gt 0) {
        throw 'CHAR2_PORT_CLAIMED_BY_OTHER_PROCESS'
    }
    $stdout = Get-Content -LiteralPath (Join-Path $evidence 'char2-server.stdout.log') -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath (Join-Path $evidence 'char2-server.stderr.log') -Raw -ErrorAction SilentlyContinue
    if ($stderr -match 'SCRIPT ERROR:|Parse Error:|Compile Error:') {
        throw 'CHAR2_SERVER_SCRIPT_ERROR: inspect evidence/char2-server.stderr.log'
    }
    $runtimeReady = $stdout -match '"event"\s*:\s*"node_ready"'
    if ($bound -and $runtimeReady) { break }
}
if (-not ($bound -and $runtimeReady)) {
    throw ("CHAR2_SERVER_READY_TIMEOUT: bind={0} world_ready={1} budget={2}s; inspect server logs" -f $bound,$runtimeReady,$StartupTimeoutSeconds)
}

function Start-CHAR2Client([string] $Player, [int] $X) {
    $argsList = @(
        '--rendering-driver','opengl3',
        '--windowed','--resolution','900x600','--position',('{0},60' -f $X),
        '--path',$quoted,'--',
        '--role=game-client','--network-mvp','--world=earth',
        '--server-address=127.0.0.1',('--server-port={0}' -f $Port),
        ('--player-identity={0}' -f $Player),
        ('--node-id=char2-client-{0}-{1}' -f $Player,$Slot)
    )
    return Start-Process -FilePath $godot.GUI -ArgumentList $argsList -WorkingDirectory $project -PassThru
}

$a = Start-CHAR2Client 'a' 20
$null = $a.Handle
$owned.Add($a)
$b = Start-CHAR2Client 'b' 960
$null = $b.Handle
$owned.Add($b)
Start-Sleep -Seconds 3
foreach ($process in @($a,$b)) {
    $null = $process.Handle
    if ($process.HasExited) {
        throw ("CHAR2_CLIENT_EXITED_IMMEDIATELY:{0}" -f $process.ExitCode)
    }
}

$report = [ordered]@{
    schema = 'dws.char2.two_gui_client_launcher.v1'
    product_head = $identity.product_head
    product_tree = $identity.product_tree
    port = $Port
    persistence_slot = $Slot
    dedicated_server_pid = $server.Id
    client_a_pid = $a.Id
    client_b_pid = $b.Id
    startup = 'SERVER_BOUND_AND_WORLD_READY_TWO_CLIENT_PROCESSES_ALIVE'
    startup_budget_seconds = $StartupTimeoutSeconds
    client_connection_acceptance = 'PENDING'
    graphical_acceptance = 'PENDING_USER_CONFIRMATION'
    first_person_local_body = 'HIDDEN'
    third_person_local_body = 'VISIBLE'
    remote_avatar = 'avatar/quaternius'
    started_at = (Get-Date).ToString('o')
}
$report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence 'char2-two-gui-client-launch.json') -Encoding UTF8

Write-Host ''
Write-Host 'CHAR2 REAL SERVER + TWO GUI CLIENTS STARTED' -ForegroundColor Green
Write-Host ("server PID: {0}  UDP port: {1}" -f $server.Id,$Port)
Write-Host ("client A PID: {0}  client B PID: {1}" -f $a.Id,$b.Id)
Write-Host 'In window A: see real Quaternius player B; in window B: see player A.'
Write-Host 'Press V/F7 in the focused client to switch FIRST_PERSON (self hidden) / THIRD_PERSON (self visible).'
Write-Host 'Press F1 for character.camera.status or network.jitter.snapshot.'
Write-Host 'Keep all windows open for manual testing. Successful sessions remain running.'
$launchSucceeded = $true
}
finally {
    if (-not $launchSucceeded) {
        # Only handles created by this invocation. Never kill a foreign Godot
        # process, an existing world session, or all processes by executable name.
        foreach ($process in $owned) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(10000) | Out-Null }
            } catch { Write-Warning $_.Exception.Message }
        }
    }
}
