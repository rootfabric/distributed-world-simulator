[CmdletBinding()]
param([string]$GodotConsole='', [string]$AssetSource='', [int]$Port=24580,
      [string]$Slot='', [ValidateRange(30,900)][int]$StartupTimeoutSeconds=240, [switch]$SkipImport)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Playtest-Common.ps1')
$package=Get-CHAR1Root;$project=Join-Path $package 'project'
$identity=Assert-CHAR1Snapshot $package
$godot=Resolve-CHAR1Godot $GodotConsole
if($Port -lt 1024 -or $Port -gt 65535){throw 'INVALID_TEST_PORT'}
if([string]::IsNullOrWhiteSpace($Slot)){$Slot='test-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+([guid]::NewGuid().ToString('N').Substring(0,6))}
if($Slot -notmatch '^[a-z0-9][a-z0-9_-]{0,47}$'){throw 'INVALID_TEST_SLOT'}
if(@(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue).Count -gt 0){throw "UDP $Port already occupied; stop only your old session or select -Port"}
Assert-PlaytestAssets -Package $package -GodotConsole $godot.Console -AssetSource $AssetSource -SkipImport:$SkipImport
$evidence=Join-Path $package ('evidence/session-'+$Slot)
New-Item -ItemType Directory -Force $evidence | Out-Null
$quoted='"{0}"' -f $project
$build=@('--network-build-id=dws-playtest-r1-safe60',('--network-git-commit='+$identity.product_head),'--print-runtime-descriptor')
$serverArgs=@('--headless','--max-fps','60','--disable-vsync','--path',$quoted,'--','--role=dedicated-server','--network-mvp','--product-seam','--world=earth','--server-address=127.0.0.1',('--server-port='+$Port),('--instance-id='+$Slot),('--node-id=playtest-server-'+$Slot))+$build
$owned=[System.Collections.Generic.List[System.Diagnostics.Process]]::new();$success=$false
try {
    # Start the actual engine directly in headless mode, not its console wrapper.
    # Thus the process we own is the UDP owner, avoiding wrapper-child PID races.
    $server=Start-PlaytestProcess -Executable $godot.GUI -Package $package -Role server -Identity ('server-'+$Port) -LaunchArguments $serverArgs -LogPrefix (Join-Path $evidence 'server')
    $owned.Add($server)
    $watch=[System.Diagnostics.Stopwatch]::StartNew();$ready=$false
    while($watch.Elapsed.TotalSeconds -lt $StartupTimeoutSeconds){
        Start-Sleep -Milliseconds 250;$server.Refresh()
        if($server.HasExited){throw "SERVER_EXITED:$($server.ExitCode)"}
        $listeners=@(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
        if(@($listeners|Where-Object {$_.OwningProcess -ne $server.Id}).Count -gt 0){throw 'FOREIGN_PROCESS_CLAIMED_PORT'}
        $bound=@($listeners|Where-Object {$_.OwningProcess -eq $server.Id}).Count -gt 0
        $log=Get-Content (Join-Path $evidence 'server.stdout.log') -Raw -ErrorAction SilentlyContinue
        $err=Get-Content (Join-Path $evidence 'server.stderr.log') -Raw -ErrorAction SilentlyContinue
        if($err -match 'SCRIPT ERROR:|Parse Error:|Compile Error:'){throw 'SERVER_SCRIPT_ERROR'}
        $ready=$bound -and ($log -match '"event"\s*:\s*"node_ready"')
        if($ready){break}
    }
    if(-not $ready){throw 'SERVER_WORLD_READY_TIMEOUT'}
    foreach($pair in @(@('a',20),@('b',950))){
        $player=[string]$pair[0];$x=[int]$pair[1]
        $clientArgs=@('--max-fps','60','--disable-vsync','--rendering-driver','opengl3','--windowed','--resolution','900x600','--position',("$x,60"),'--path',$quoted,'--','--role=game-client','--network-mvp','--world=earth','--server-address=127.0.0.1',('--server-port='+$Port),('--player-identity='+$player),('--node-id=playtest-client-'+$player),'--connect-timeout-ms=120000')+$build
        $client=Start-PlaytestProcess -Executable $godot.GUI -Package $package -Role client -Identity ('client-'+$player) -LaunchArguments $clientArgs -LogPrefix (Join-Path $evidence ('client-'+$player))
        $owned.Add($client)
    }
    Start-Sleep -Seconds 3
    foreach($process in $owned){$process.Refresh();if($process.HasExited){throw "PLAYTEST_PROCESS_EXITED:$($process.Id)"}}
    $identities=@($owned|ForEach-Object {@{pid=$_.Id;start_time=$_.StartTime.ToUniversalTime().ToString('o');exe=$_.MainModule.FileName}})
    [ordered]@{head=$identity.product_head;tree=$identity.product_tree;profile='PLAYTEST_R1_SAFE60';port=$Port;slot=$Slot;processes=$identities;server_ready=$true;gui_acceptance='PENDING_HUMAN';started=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $evidence 'session.json') -Encoding UTF8
    Copy-Item (Join-Path $evidence 'session.json') (Join-Path $package 'evidence/active-test.json') -Force
    Write-Host "DWS Playtest R1: a + b, port $Port, slot $Slot" -ForegroundColor Green
    Write-Host 'This launch uses the SAME network/character profile as Host/Join, not playground.'
    Write-Host 'Turn toward the yellow peer-direction hint; V/F7 toggles view.'
    $success=$true
} finally {
    if(-not $success){foreach($process in $owned){try{$process.Refresh();if(-not $process.HasExited){$process.Kill();$process.WaitForExit(5000)|Out-Null}}catch{Write-Warning $_.Exception.Message}}}
}
