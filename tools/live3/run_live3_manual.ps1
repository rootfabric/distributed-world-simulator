#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [ValidatePattern('^[a-z0-9_-]{1,48}$')][string]$Slot = 'outpost',
    [string]$DataRoot = 'C:\distributed-world-simulator\live3-data',
    [ValidateRange(1024,65535)][int]$Port = 24580,
    [string]$ExpectedHead = '',
    [string]$GodotConsole = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe',
    [string]$GodotGui = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe'
)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path $Repo).Path
if ($Repo -match '[\\/]runner[\\/].*[\\/]_work[\\/]') { throw 'DO_NOT_USE_RUNNER_CHECKOUT' }
if ($Slot -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') { throw 'RESERVED_WORLD_SLOT' }
$head = & git -C $Repo rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or -not $head) { throw 'REPO_IS_NOT_A_GIT_CHECKOUT' }
$head = $head.Trim()
$tree = & git -C $Repo rev-parse 'HEAD^{tree}'
if ($LASTEXITCODE -ne 0 -or -not $tree) { throw 'TREE_READ_FAILED' }
$tree = $tree.Trim()
if ($ExpectedHead -and $ExpectedHead -ne $head) { throw 'EXPECTED_HEAD_MISMATCH' }
$dirty = & git -C $Repo status --porcelain --untracked-files=no
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'TRACKED_CHECKOUT_NOT_CLEAN' }
foreach ($entry in @(
    @($GodotConsole,'3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'),
    @($GodotGui,'6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4')
)) {
    if (-not (Test-Path -LiteralPath $entry[0])) { throw ('GODOT_NOT_FOUND:' + $entry[0]) }
    if ((Get-FileHash -LiteralPath $entry[0] -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry[1]) { throw 'GODOT_HASH_MISMATCH' }
}
$foreign = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'godot*' -or $_.ProcessName -eq 'Runner.Worker' })
if ($foreign.Count) {
    $foreign | Select-Object Id,ProcessName | Format-Table
    throw 'BLOCKED_BY_ACTIVE_CI_OR_FOREIGN_GODOT'
}
if (Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue) { throw "UDP_PORT_IN_USE:$Port" }
if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB / 1GB -lt 10) { throw 'LESS_THAN_10GB_FREE_RAM' }
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
$Worlds = Join-Path $DataRoot 'worlds'
$Profiles = Join-Path (Join-Path $DataRoot 'profiles') $Slot
$Locks = Join-Path $DataRoot 'locks'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$Session = Join-Path $Repo "artifacts\live3-manual\$stamp"
New-Item -ItemType Directory -Force $Worlds,$Profiles,$Locks,$Session | Out-Null
$slotLock = $null
$script:Server = $null
$script:Clients = @{a=$null;b=$null}
$script:LaunchNumber = 0

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}
function Quote-Arguments([string[]]$Values) {
    foreach ($value in $Values) {
        if ($value.Contains('"') -or $value.EndsWith('\')) { throw 'UNSUPPORTED_QUOTING_IN_ARGUMENT' }
        '"' + $value + '"'
    }
}
function Start-Owned([string]$Exe,[string[]]$Values,[string]$Name,[string]$Profile) {
    New-Item -ItemType Directory -Force $Profile | Out-Null
    $arguments = (Quote-Arguments $Values) -join ' '
    $environment = @{
        APPDATA=$Profile;LOCALAPPDATA=$Profile
        BREAKPOINT_RUNTIME_DISABLED='1';GODOT_SILENCE_ROOT_WARNING='1'
        PLANET_SIMULATOR_INVENTORY_PROFILE='planet_default'
    }
    Start-Process -FilePath $Exe -ArgumentList $arguments -WorkingDirectory $Repo -Environment $environment `
        -RedirectStandardOutput (Join-Path $Session "$Name.stdout.log") `
        -RedirectStandardError (Join-Path $Session "$Name.stderr.log") -PassThru
}
function Start-Server {
    $script:LaunchNumber++
    $name = 'server-' + $script:LaunchNumber
    $control = Join-Path $Session "$name.control.json"
    $status = Join-Path $Session "$name.status.json"
    $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $values = @('--headless','--path',$Repo,'--log-file',(Join-Path $Session "$name.log"),'--',
        '--network-mvp','--role=dedicated-server','--world=earth',"--server-port=$Port",'--network-debug',
        "--world-slot=$Slot","--world-save-root=$Worlds","--world-control-file=$control", "--world-control-token=$token",
        "--world-status-file=$status",('--m6-result-file=' + (Join-Path $Session "$name.native.json")))
    $process = Start-Owned $GodotConsole $values $name (Join-Path $Profiles 'server')
    $script:Server = @{Process=$process;Control=$control;Status=$status;Token=$token;Name=$name;RealPid=0}
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) { throw "SERVER_START_FAILED:$($process.ExitCode); logs=$Session" }
        $result = Read-Json $status
        if ($result -and $result.phase -eq 'FAILED') { throw ('SERVER_RECOVERY_FAILED:' + ($result | ConvertTo-Json -Compress)) }
        if ($result -and $result.phase -eq 'READY') {
            $script:Server.RealPid = [int]$result.process_id
            $endpoint = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $endpoint -or [int]$endpoint.OwningProcess -ne $script:Server.RealPid) { throw 'SERVER_UDP_OWNER_MISMATCH' }
            Write-Host "World '$Slot' READY. Recovered=$($result.recovered), generation=$($result.generation), PID=$($result.process_id)"
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw "SERVER_READY_TIMEOUT; logs=$Session"
}
function Stop-Server {
    if ($null -eq $script:Server) { return }
    $server = $script:Server
    $server.Process.Refresh()
    if ($server.Process.HasExited) {
        $status = Read-Json $server.Status
        if ($server.Process.ExitCode -ne 0 -or -not $status -or $status.saved -ne $true) { throw 'SERVER_EXITED_WITHOUT_CONFIRMED_SAVE' }
        $script:Server=$null
        return
    }
    if ($server.RealPid -le 0) { throw 'SERVER_NOT_READY_NO_SAFE_STOP_CAPABILITY' }
    $request = @{schema='dws.live3.host_request.v1';action='SAVE_AND_STOP';token=$server.Token;process_id=$server.RealPid;request_id=[guid]::NewGuid().ToString('N')}
    $temp = $server.Control + '.pending'
    $request | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $server.Control -Force
    if (-not $server.Process.WaitForExit(40000)) { throw 'SAVE_TIMEOUT_SERVER_NOT_KILLED' }
    $server.Process.Refresh()
    $status = Read-Json $server.Status
    if ($server.Process.ExitCode -ne 0 -or -not $status -or $status.phase -ne 'STOPPED' -or $status.saved -ne $true) {
        throw "SAVE_FAILED_NO_RESTART; inspect $($server.Status)"
    }
    if (Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue) { throw 'SERVER_UDP_STILL_BOUND_AFTER_STOP' }
    Write-Host "World saved, generation=$($status.generation)."
    $script:Server=$null
}
function Start-Client([ValidateSet('a','b')][string]$Identity) {
    $existing=$script:Clients[$Identity]
    if ($null -ne $existing) {
        $existing.Refresh()
        if (-not $existing.HasExited) { throw "CLIENT_ALREADY_RUNNING:$Identity" }
    }
    $script:LaunchNumber++
    $name="client-$Identity-$($script:LaunchNumber)"
    $position=if ($Identity -eq 'a') {'20,50'} else {'960,50'}
    $values=@('--path',$Repo,'--resolution','900x650','--position',$position,'--log-file',(Join-Path $Session "$name.log"),'--',
        '--network-mvp','--role=game-client','--world=earth','--server-address=127.0.0.1',"--server-port=$Port",
        "--player-identity=$Identity", "--node-id=live3-manual-$Identity",'--network-debug','--network-debug-stay-open')
    $script:Clients[$Identity] = Start-Owned $GodotGui $values $name (Join-Path $Profiles "client-$Identity")
    Write-Host "Client $Identity started, PID=$($script:Clients[$Identity].Id)."
}
function Stop-Client([ValidateSet('a','b')][string]$Identity) {
    $process=$script:Clients[$Identity]
    if ($null -eq $process) { return }
    $process.Refresh()
    if (-not $process.HasExited) {
        if (-not $process.CloseMainWindow()) { throw "CLOSE_CLIENT_WINDOW_MANUALLY:$Identity" }
        if (-not $process.WaitForExit(15000)) { throw "CLIENT_CLOSE_TIMEOUT_NOT_KILLED:$Identity" }
    }
    $script:Clients[$Identity]=$null
}
try {
    $slotLock = [IO.File]::Open((Join-Path $Locks "$Slot.lock"),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    @{head=$head;tree=$tree;slot=$Slot;worlds=$Worlds;session=$Session;port=$Port;started_at=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $Session 'session.json')
    # Mandatory on every checkout; separate profile avoids changing personal data.
    $import = Start-Owned $GodotConsole @('--headless','--path',$Repo,'--editor','--import','--quit') 'import' (Join-Path $Session 'import-profile')
    if (-not $import.WaitForExit(900000)) { throw 'IMPORT_TIMEOUT_OWNED_PROCESS_NOT_KILLED' }
    $import.Refresh()
    $errors = @(Select-String -Path (Join-Path $Session 'import.*.log') -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script')
    if ($import.ExitCode -ne 0 -or $errors.Count -gt 0) { throw "IMPORT_FAILED; logs=$Session" }
    Start-Server
    Start-Client a
    Start-Client b
    Write-Host "Logs: $Session"
    Write-Host "Persistent world: $(Join-Path $Worlds $Slot)"
    while ($true) {
        Write-Host '[A] restart client A  [B] restart client B  [R] save/restart server (clients stay open)  [Q] save and quit'
        $choice=(Read-Host 'Action').Trim().ToUpperInvariant()
        switch ($choice) {
            'A' { Stop-Client a; Start-Client a }
            'B' { Stop-Client b; Start-Client b }
            'R' { Stop-Server; Start-Server; Write-Host 'Clients should reconnect automatically to the same world.' }
            'Q' { Stop-Client a; Stop-Client b; Stop-Server; return }
            default { Write-Host 'Use A, B, R or Q.' }
        }
    }
} finally {
    # A failed save is never converted into force-kill or successful shutdown.
    if ($null -ne $script:Server) {
        try { Stop-Server } catch { Write-Warning "World was NOT confirmed saved: $($_.Exception.Message)" }
    }
    foreach ($identity in @('a','b')) {
        try { Stop-Client $identity } catch { Write-Warning $_.Exception.Message }
    }
    if ($null -ne $slotLock) { $slotLock.Dispose() }
    Write-Host "Session evidence preserved: $Session"
}
