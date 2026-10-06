param(
    [Parameter(Mandatory=$true)][string]$Worktree,
    [Parameter(Mandatory=$true)][string]$ExpectedProductHead,
    [Parameter(Mandatory=$true)][string]$ExpectedProductTree,
    [string]$GodotGui="C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [string]$GodotConsole="C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [int]$ServerPort=24680,
    [int]$ClientAPort=28651,
    [int]$ClientBPort=28652,
    [string]$SessionRoot=""
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$Worktree=(Resolve-Path $Worktree).Path
$CarrierHead=(git -C $Worktree rev-parse HEAD).Trim()
$ProductHead=$ExpectedProductHead.Trim()
$ProductTree=$ExpectedProductTree.Trim()
if((git -C $Worktree rev-parse "$ProductHead^{tree}").Trim()-ne$ProductTree){throw 'PRODUCT_TREE_MISMATCH'}
$carrierDiff=@(git -C $Worktree diff --name-only $ProductHead $CarrierHead)
$allowed=@('.github/workflows/user1-r3-gui-seam-smoke.yml','tools/live2/run_user1_r3_gui_seam_smoke.ps1')
if(@($carrierDiff|Where-Object{$_-notin$allowed}).Count-gt0){throw "CARRIER_SCOPE_VIOLATION:$($carrierDiff-join',')"}
$Stamp=Get-Date -Format "yyyyMMdd-HHmmss"
if([string]::IsNullOrWhiteSpace($SessionRoot)){
    $SessionRoot=Join-Path $env:RUNNER_TEMP "user1-r3-gui-smoke-$Stamp"
}
New-Item -ItemType Directory -Force $SessionRoot|Out-Null
$SessionRoot=(Resolve-Path $SessionRoot).Path
$Cli=Join-Path $Worktree "tools\live2\live2_automation_client.py"
if(-not(Test-Path $Cli)){throw "AUTOMATION_CLI_NOT_FOUND:$Cli"}
foreach($bin in @($GodotGui,$GodotConsole)){if(-not(Test-Path $bin)){throw "GODOT_NOT_FOUND:$bin"}}
$ExpectedWinSha='3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'
if((Get-FileHash $GodotConsole -Algorithm SHA256).Hash.ToLowerInvariant()-ne$ExpectedWinSha){throw 'GODOT_CONSOLE_SHA_MISMATCH'}
if((&$GodotConsole --version|Out-String).Trim()-ne'4.7.1.stable.double.custom_build.a13da4feb'){throw 'GODOT_VERSION_MISMATCH'}
$Foreign=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -like 'godot*'})
if($Foreign.Count-gt0){throw "FOREIGN_GODOT_PROCESS:$((($Foreign|Select-Object -ExpandProperty Id)-join','))"}

$Token=([guid]::NewGuid().ToString("N")+[guid]::NewGuid().ToString("N"))
$Profiles=Join-Path $SessionRoot "profiles"
$ServerProfile=Join-Path $Profiles "server"
$ClientAProfile=Join-Path $Profiles "client-a"
$ClientBProfile=Join-Path $Profiles "client-b"
$AutomationA=Join-Path $SessionRoot "automation-a"
$AutomationB=Join-Path $SessionRoot "automation-b"
foreach($dir in @($ServerProfile,$ClientAProfile,$ClientBProfile,$AutomationA,$AutomationB)){New-Item -ItemType Directory -Force $dir|Out-Null}
$ServerLog=Join-Path $SessionRoot "server.log"
$ClientALog=Join-Path $SessionRoot "client-a.log"
$ClientBLog=Join-Path $SessionRoot "client-b.log"
$ActionLog=Join-Path $SessionRoot "actions.jsonl"
$ReportPath=Join-Path $SessionRoot "USER1-R3-GUI-SMOKE.json"
$Processes=[ordered]@{}
$Actions=@()
$Outcome="UNKNOWN"
$Failure=""

function Write-JsonLine{param($Value,[string]$Path);($Value|ConvertTo-Json -Depth 80 -Compress)|Add-Content $Path -Encoding UTF8}
function Wait-UdpOwner{
    param([int]$Port,[int]$TimeoutSeconds=30)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $e=Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue|Select-Object -First 1
        if($null-ne$e-and[int]$e.OwningProcess-gt0){return[int]$e.OwningProcess}
        Start-Sleep -Milliseconds 250
    }
    throw "UDP_OWNER_TIMEOUT:$Port"
}
function Invoke-Control{
    param([ValidateSet("A","B")][string]$Client,[string[]]$Arguments,[switch]$AllowFailure)
    $port=if($Client-eq"A"){$ClientAPort}else{$ClientBPort}
    $raw=& python $Cli --port $port --token $Token @Arguments 2>&1|Out-String
    $code=$LASTEXITCODE;$parsed=$null
    try{$parsed=$raw|ConvertFrom-Json -Depth 100}catch{}
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString('o');client=$Client;arguments=$Arguments;exit_code=$code;response=$parsed;raw=if($null-eq$parsed){$raw.Trim()}else{$null}}) $ActionLog
    if($code-ne0-and-not$AllowFailure){throw "AUTOMATION_COMMAND_FAILED:$Client:$($Arguments-join' '):$raw"}
    return $parsed
}
function Wait-Ready{
    param([ValidateSet("A","B")][string]$Client)
    $deadline=(Get-Date).AddSeconds(60)
    while((Get-Date)-lt$deadline){
        try{$r=Invoke-Control $Client @("ping") -AllowFailure;if($null-ne$r-and[bool]$r.ok){return}}catch{}
        Start-Sleep -Milliseconds 400
    }
    throw "AUTOMATION_NOT_READY:$Client"
}
function Get-AutomationState{param([ValidateSet("A","B")][string]$Client);return Invoke-Control $Client @("state","--kind","automation")}
function Wait-Connected{
    param([ValidateSet("A","B")][string]$Client,[int]$TimeoutSeconds=60)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        try{$s=Get-AutomationState $Client;if([string]$s.result.automation.connection_state-eq"CONNECTED"){return}}catch{}
        Start-Sleep -Milliseconds 400
    }
    throw "CLIENT_CONNECT_TIMEOUT:$Client"
}
function Get-RuntimeState{param([ValidateSet("A","B")][string]$Client);return Invoke-Control $Client @("state","--kind","runtime")}
function Get-JourneyState{
    param([ValidateSet("A","B")][string]$Client)
    $s=Get-RuntimeState $Client
    try{return $s.result.snapshot.runtime.m3_spectator.user1_journey.last_state}catch{return $null}
}
function Drive-UntilRegion{
    param([ValidateSet("A","B")][string]$Client,[string]$Region,[double]$X,[int]$TimeoutSeconds=45)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $args=@("move","--x",$X.ToString([cultureinfo]::InvariantCulture),"--z","0","--yaw","0.4251206143591745","--ttl-ms","900","--sprint")
        Invoke-Control $Client $args|Out-Null
        Start-Sleep -Milliseconds 350
        $journey=Get-JourneyState $Client
        Write-JsonLine ([ordered]@{at=(Get-Date).ToString('o');event='REGION_POLL';client=$Client;target=$Region;state=$journey}) $ActionLog
        if($null-ne$journey-and[string]$journey.region_id-eq$Region){
            Invoke-Control $Client @("stop")|Out-Null
            return $journey
        }
    }
    Invoke-Control $Client @("stop") -AllowFailure|Out-Null
    throw "REGION_TIMEOUT:$Client:$Region"
}
function Gameplay{
    param([ValidateSet("A","B")][string]$Client,[string]$Line,[string]$Label,[bool]$RequireSuccess=$false)
    $r=Invoke-Control $Client @("command",$Line) -AllowFailure
    $json=if($null-ne$r){$r|ConvertTo-Json -Depth 100 -Compress}else{""}
    if($json-match'USER1_SEAM_GAMEPLAY_MUTATION_FROZEN'){throw "SEAM_MUTATION_FROZEN:$Label"}
    if($RequireSuccess-and($null-eq$r-or-not[bool]$r.ok)){throw "GAMEPLAY_REQUIRED_SUCCESS_FAILED:$Label:$json"}
    $row=[ordered]@{label=$Label;command=$Line;response=$r}
    $script:Actions+=$row
    Start-Sleep -Seconds 2
    return $row
}
function Find-ServerReport{
    $f=Get-ChildItem -LiteralPath $ServerProfile -Filter 'v0-s1-network-mvp-runtime.json' -File -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
    return $f
}
function Read-ServerReport{
    $deadline=(Get-Date).AddSeconds(20)
    while((Get-Date)-lt$deadline){
        $f=Find-ServerReport
        if($null-ne$f){
            try{return Get-Content $f.FullName -Raw|ConvertFrom-Json -Depth 100}catch{}
        }
        Start-Sleep -Milliseconds 300
    }
    throw 'SERVER_RUNTIME_REPORT_NOT_FOUND'
}
function Save-ServerReport{param([string]$Name);$r=Read-ServerReport;$r|ConvertTo-Json -Depth 100|Set-Content (Join-Path $SessionRoot "$Name.json") -Encoding UTF8;return $r}

try{
    [ordered]@{schema='dws.user1.r3.gui_seam_smoke.v1';product_head=$ProductHead;product_tree=$ProductTree;created_at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $SessionRoot 'session.json') -Encoding UTF8

    $instance="user1-r3-gui-smoke-$Stamp"
    $serverArgs=@("--headless","--path",$Worktree,"--log-file",$ServerLog,"--","--network-mvp","--product-seam","--role=dedicated-server","--world=earth","--server-address=127.0.0.1","--server-port=$ServerPort","--node-id=user1-r3-smoke-server","--instance-id=$instance","--network-debug")
    $Processes.server_wrapper=Start-Process -FilePath $GodotConsole -ArgumentList $serverArgs -WorkingDirectory $Worktree -Environment @{APPDATA=$ServerProfile;LOCALAPPDATA=$ServerProfile} -PassThru
    Start-Sleep -Seconds 1
    $serverPid=Wait-UdpOwner -Port $ServerPort
    $Processes.server=Get-Process -Id $serverPid -ErrorAction Stop

    $common=@("--path",$Worktree,"--resolution","900x650","--","--network-mvp","--role=game-client","--world=earth","--server-address=127.0.0.1","--server-port=$ServerPort","--network-debug","--network-debug-stay-open","--automation-control","--automation-control-token=$Token")
    $argsA=@("--position","20,50","--log-file",$ClientALog)+$common+@("--player-identity=a","--node-id=user1-r3-smoke-a","--automation-control-port=$ClientAPort","--automation-control-output-dir=$AutomationA")
    $argsB=@("--position","960,50","--log-file",$ClientBLog)+$common+@("--player-identity=b","--node-id=user1-r3-smoke-b","--automation-control-port=$ClientBPort","--automation-control-output-dir=$AutomationB")
    $Processes.a=Start-Process -FilePath $GodotGui -ArgumentList $argsA -WorkingDirectory $Worktree -Environment @{APPDATA=$ClientAProfile;LOCALAPPDATA=$ClientAProfile} -PassThru
    $Processes.b=Start-Process -FilePath $GodotGui -ArgumentList $argsB -WorkingDirectory $Worktree -Environment @{APPDATA=$ClientBProfile;LOCALAPPDATA=$ClientBProfile} -PassThru

    Wait-Ready A;Wait-Ready B;Wait-Connected A;Wait-Connected B
    Start-Sleep -Seconds 2
    $baseline=Save-ServerReport 'server-baseline'
    if([int]$baseline.fast_join_acks-lt2){throw "FAST_JOIN_INITIAL_ACKS_MISSING:$($baseline.fast_join_acks)"}
    if([string]$baseline.live2_r3_diagnostics.last_slow_handler-eq'JOIN'){throw "SLOW_JOIN_PRESENT_AT_BASELINE:$($baseline.live2_r3_diagnostics.max_handler_ms)"}

    $onB=Drive-UntilRegion A 'region/user1/b' 1.0 50
    if([int]$onB.seam_crossings-lt1){throw 'SEAM_CROSSING_NOT_RECORDED'}

    Gameplay A 'inventory.hotbar.select 1' 'remote-hotbar' $true|Out-Null
    Gameplay A 'tool.mining.equip' 'remote-equip' $false|Out-Null
    Gameplay A 'player.interact' 'remote-interact' $false|Out-Null
    $duringB=Save-ServerReport 'server-on-b'
    $duringJson=$duringB.live2_r3_diagnostics.reason_counts|ConvertTo-Json -Depth 30 -Compress
    if($duringJson-match'USER1_SEAM_GAMEPLAY_MUTATION_FROZEN'){throw "REMOTE_GAMEPLAY_STILL_FROZEN:$duringJson"}

    $backA=Drive-UntilRegion A 'region/user1/a' -1.0 50
    if([int]$backA.seam_roundtrips-lt1){throw "SEAM_ROUNDTRIP_NOT_RECORDED:$($backA.seam_roundtrips)"}
    Start-Sleep -Seconds 2
    $preReconnect=Save-ServerReport 'server-pre-reconnect'

    Gameplay A 'network.reconnect' 'reconnect' $true|Out-Null
    Wait-Connected A 60
    Start-Sleep -Seconds 3
    $final=Save-ServerReport 'server-final'

    if([int]$final.fast_join_acks-lt3){throw "FAST_JOIN_RECONNECT_ACK_MISSING:$($final.fast_join_acks)"}
    if([string]$final.live2_r3_diagnostics.last_slow_handler-eq'JOIN'){throw "SLOW_JOIN_AFTER_RECONNECT:$($final.live2_r3_diagnostics.max_handler_ms)"}
    $finalReasons=$final.live2_r3_diagnostics.reason_counts|ConvertTo-Json -Depth 40 -Compress
    if($finalReasons-match'USER1_SEAM_GAMEPLAY_MUTATION_FROZEN'){throw "FINAL_SEAM_FREEZE_REJECTION_PRESENT:$finalReasons"}
    if([int]$final.service.user1_product_seam.transfer_failures-ne0){throw "SEAM_TRANSFER_FAILURE:$($final.service.user1_product_seam.transfer_failures)"}
    if([int]$final.service.user1_product_seam.active_binding_count-ne0){throw "SEAM_BINDING_NOT_RELEASED:$($final.service.user1_product_seam.active_binding_count)"}
    if([int]$final.service.user1_product_seam.players.a.roundtrips-lt1){throw 'FINAL_ROUNDTRIP_MISSING'}

    $Outcome='PASS'
    [ordered]@{
        schema='dws.user1.r3.gui_seam_smoke.result.v1'
        outcome=$Outcome
        product_head=$ProductHead
        product_tree=$ProductTree
        baseline_fast_join_acks=[int]$baseline.fast_join_acks
        final_fast_join_acks=[int]$final.fast_join_acks
        baseline_handlers_over_50ms=[int]$baseline.live2_r3_diagnostics.handlers_over_50ms
        pre_reconnect_handlers_over_50ms=[int]$preReconnect.live2_r3_diagnostics.handlers_over_50ms
        final_handlers_over_50ms=[int]$final.live2_r3_diagnostics.handlers_over_50ms
        final_max_handler_ms=[double]$final.live2_r3_diagnostics.max_handler_ms
        final_last_slow_handler=[string]$final.live2_r3_diagnostics.last_slow_handler
        baseline_catch_up_batches=[int]$baseline.fixed_tick_simulation.catch_up_batches
        final_catch_up_batches=[int]$final.fixed_tick_simulation.catch_up_batches
        catch_up_delta=([int]$final.fixed_tick_simulation.catch_up_batches-[int]$baseline.fixed_tick_simulation.catch_up_batches)
        transfers=[int]$final.service.user1_product_seam.transfer_serial
        transfer_failures=[int]$final.service.user1_product_seam.transfer_failures
        roundtrips=[int]$final.service.user1_product_seam.players.a.roundtrips
        active_binding_count=[int]$final.service.user1_product_seam.active_binding_count
        mutation_freeze_reason_present=($finalReasons-match'USER1_SEAM_GAMEPLAY_MUTATION_FROZEN')
        actions=$Actions
        completed_at=(Get-Date).ToString('o')
    }|ConvertTo-Json -Depth 100|Set-Content $ReportPath -Encoding UTF8
}catch{
    $Outcome='FAIL';$Failure=$_.Exception.Message
    [ordered]@{schema='dws.user1.r3.gui_seam_smoke.result.v1';outcome=$Outcome;failure=$Failure;product_head=$ProductHead;product_tree=$ProductTree;actions=$Actions;completed_at=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 100|Set-Content $ReportPath -Encoding UTF8
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString('o');event='FAIL';error=$Failure}) $ActionLog
}finally{
    foreach($client in @('A','B')){try{Invoke-Control $client @('stop') -AllowFailure|Out-Null}catch{}}
    foreach($client in @('A','B')){try{Invoke-Control $client @('command','app.quit') -AllowFailure|Out-Null}catch{}}
    Start-Sleep -Seconds 3
    foreach($name in @('a','b','server','server_wrapper')){
        if($Processes.Contains($name)){
            try{$p=$Processes[$name];$p.Refresh();if(-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}}catch{}
        }
    }
    $remaining=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -like 'godot*'})
    [ordered]@{remaining_godot_pids=@($remaining|Select-Object -ExpandProperty Id);udp_free=($null-eq(Get-NetUDPEndpoint -LocalPort $ServerPort -ErrorAction SilentlyContinue))}|ConvertTo-Json -Depth 10|Set-Content (Join-Path $SessionRoot 'cleanup.json') -Encoding UTF8
}
Write-Host "USER1_R3_GUI_SMOKE=$Outcome"
Write-Host "SESSION=$SessionRoot"
Write-Host "REPORT=$ReportPath"
if($Outcome-ne'PASS'){throw "USER1_R3_GUI_SMOKE_FAILED:$Failure"}
