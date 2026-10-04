param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [string]$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [int]$ServerPort = 24580,
    [int]$ClientAPort = 28651,
    [int]$ClientBPort = 28652,
    [int]$PhaseOneServerLifetimeSeconds = 90,
    [string]$SessionRoot = "",
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"
$Worktree = (Resolve-Path $Worktree).Path
$ProductHead = (git -C $Worktree rev-parse HEAD).Trim()
$ProductTree = (git -C $Worktree rev-parse 'HEAD^{tree}').Trim()
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $SessionRoot = Join-Path $Worktree "artifacts\live3-product-recovery\$Stamp"
}
New-Item -ItemType Directory -Force $SessionRoot | Out-Null
$SessionRoot = (Resolve-Path $SessionRoot).Path

$Cli = Join-Path $Worktree "tools\live2\live2_automation_client.py"
if (-not (Test-Path $Cli)) { throw "AUTOMATION_CLI_NOT_FOUND:$Cli" }
foreach ($binary in @($GodotGui,$GodotConsole)) {
    if (-not (Test-Path $binary)) { throw "GODOT_NOT_FOUND:$binary" }
}

$Foreign = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" })
if ($Foreign.Count -gt 0) {
    throw "FOREIGN_GODOT_PROCESS:$((($Foreign | Select-Object -ExpandProperty Id) -join ','))"
}

if (-not $SkipImport) {
    if (Test-Path (Join-Path $Worktree ".godot")) {
        Remove-Item (Join-Path $Worktree ".godot") -Recurse -Force
    }
    $ImportLog = Join-Path $SessionRoot "import.log"
    & $GodotConsole --headless --path $Worktree --editor --import --quit *> $ImportLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content $ImportLog -Tail 300
        throw "COLD_IMPORT_FAILED:$LASTEXITCODE"
    }
    if (Select-String -Path $ImportLog -Pattern 'SCRIPT ERROR:|Parse Error:|Compile Error:' -Quiet) {
        Get-Content $ImportLog -Tail 300
        throw "COLD_IMPORT_SCRIPT_ERRORS"
    }
}

$Token = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))
$PersistenceRoot = Join-Path $SessionRoot "persistence"
$Profiles = Join-Path $SessionRoot "profiles"
$Logs = Join-Path $SessionRoot "logs"
$AutomationA = Join-Path $SessionRoot "automation-a"
$AutomationB = Join-Path $SessionRoot "automation-b"
foreach($dir in @(
    $PersistenceRoot,$Profiles,$Logs,$AutomationA,$AutomationB,
    (Join-Path $Profiles "server-1"),
    (Join-Path $Profiles "server-2"),
    (Join-Path $Profiles "client-a-1"),
    (Join-Path $Profiles "client-a-2"),
    (Join-Path $Profiles "client-b")
)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
}

$ActionLog = Join-Path $SessionRoot "actions.jsonl"
$ReportPath = Join-Path $SessionRoot "LIVE3-RECOVERY-REPORT.json"
$Processes = [ordered]@{}
$Observations = [ordered]@{}
$Outcome = "UNKNOWN"
$Failure = ""

function Write-JsonLine {
    param($Value,[string]$Path)
    ($Value | ConvertTo-Json -Depth 60 -Compress) | Add-Content -Path $Path -Encoding UTF8
}

function Invoke-Control {
    param(
        [ValidateSet("A","B")][string]$Client,
        [string[]]$Arguments,
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 8
    )
    $Port = if($Client -eq "A"){$ClientAPort}else{$ClientBPort}
    $Raw = & python $Cli --port $Port --token $Token --timeout $TimeoutSeconds @Arguments 2>&1 | Out-String
    $Code = $LASTEXITCODE
    $Parsed = $null
    try { $Parsed = $Raw | ConvertFrom-Json -Depth 80 } catch {}
    Write-JsonLine ([ordered]@{
        at=(Get-Date).ToString("o")
        client=$Client
        arguments=$Arguments
        exit_code=$Code
        response=$Parsed
        raw=if($null-eq$Parsed){$Raw.Trim()}else{$null}
    }) $ActionLog
    if($Code -ne 0 -and -not $AllowFailure){
        throw "AUTOMATION_COMMAND_FAILED:$($Client):$($Arguments -join ' '):$Raw"
    }
    return $Parsed
}

function Get-AutomationState {
    param([ValidateSet("A","B")][string]$Client)
    $r=Invoke-Control $Client @("state","--kind","automation")
    if($null-eq$r -or -not [bool]$r.ok){throw "AUTOMATION_STATE_FAILED:$($Client)"}
    return $r.result.automation
}

function Get-JitterState {
    param([ValidateSet("A","B")][string]$Client)
    $r=Invoke-Control $Client @("state","--kind","jitter")
    if($null-eq$r -or -not [bool]$r.ok){throw "JITTER_STATE_FAILED:$($Client)"}
    return $r.result.jitter
}

function Wait-Bridge {
    param([ValidateSet("A","B")][string]$Client,[int]$TimeoutSeconds=60)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        try{
            $r=Invoke-Control $Client @("ping") -AllowFailure -TimeoutSeconds 3
            if($null-ne$r -and [bool]$r.ok){return}
        }catch{}
        Start-Sleep -Milliseconds 400
    }
    throw "AUTOMATION_BRIDGE_TIMEOUT:$($Client)"
}

function Wait-ConnectionState {
    param(
        [ValidateSet("A","B")][string]$Client,
        [string[]]$States=@("CONNECTED"),
        [int]$TimeoutSeconds=75
    )
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        try{
            $s=Get-AutomationState $Client
            $state=[string]$s.connection_state
            if($States -contains $state){return $s}
        }catch{}
        Start-Sleep -Milliseconds 400
    }
    throw "CLIENT_CONNECTION_STATE_TIMEOUT:$($Client):$($States -join ',')"
}

function Wait-AsyncIdle {
    param([ValidateSet("A","B")][string]$Client,[int]$TimeoutSeconds=20)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $j=Get-JitterState $Client
        if([int]$j.async_pending -eq 0){return}
        Start-Sleep -Milliseconds 250
    }
    throw "ASYNC_IDLE_TIMEOUT:$($Client)"
}

function Wait-UdpOwner {
    param([int]$Port,[int]$TimeoutSeconds=30)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $ep=Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
        if($null-ne$ep -and [int]$ep.OwningProcess -gt 0){return [int]$ep.OwningProcess}
        Start-Sleep -Milliseconds 250
    }
    throw "UDP_OWNER_TIMEOUT:$Port"
}

function Wait-PortFree {
    param([int]$Port,[int]$TimeoutSeconds=30)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $ep=Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue
        if($null-eq$ep){return}
        Start-Sleep -Milliseconds 250
    }
    throw "UDP_PORT_NOT_RELEASED:$Port"
}

function Start-Live3Server {
    param([int]$Ordinal,[int]$ShutdownAfterMs=0)
    $Profile=Join-Path $Profiles ("server-{0}" -f $Ordinal)
    $Log=Join-Path $Logs ("server-{0}.log" -f $Ordinal)
    $Args=@(
        "--headless","--path",$Worktree,"--log-file",$Log,"--",
        "--network-mvp",
        "--role=dedicated-server",
        "--world=earth",
        "--instance-id=live3-product-recovery-r1",
        "--server-address=127.0.0.1",
        "--server-port=$ServerPort",
        "--node-id=live3-product-server",
        "--persistence-root=$PersistenceRoot",
        "--network-debug"
    )
    if($ShutdownAfterMs -gt 0){$Args += "--shutdown-after-ms=$ShutdownAfterMs"}
    $wrapper=Start-Process -FilePath $GodotConsole -ArgumentList $Args -WorkingDirectory $Worktree -Environment @{
        APPDATA=$Profile
        LOCALAPPDATA=$Profile
    } -PassThru
    $owner=Wait-UdpOwner -Port $ServerPort -TimeoutSeconds 35
    Write-JsonLine ([ordered]@{
        at=(Get-Date).ToString("o")
        event="SERVER_STARTED"
        ordinal=$Ordinal
        wrapper_pid=$wrapper.Id
        udp_owner_pid=$owner
        persistence_root=$PersistenceRoot
        shutdown_after_ms=$ShutdownAfterMs
    }) $ActionLog
    return [ordered]@{wrapper=$wrapper;owner_pid=$owner;log=$Log}
}

function Start-Live3Client {
    param(
        [ValidateSet("A","B")][string]$Client,
        [int]$Ordinal=1
    )
    $lower=$Client.ToLowerInvariant()
    $Profile=Join-Path $Profiles ("client-{0}-{1}" -f $lower,$Ordinal)
    if($Client -eq "B"){$Profile=Join-Path $Profiles "client-b"}
    $Log=Join-Path $Logs ("client-{0}-{1}.log" -f $lower,$Ordinal)
    $Port=if($Client-eq"A"){$ClientAPort}else{$ClientBPort}
    $Pos=if($Client-eq"A"){"20,50"}else{"960,50"}
    $Output=if($Client-eq"A"){$AutomationA}else{$AutomationB}
    $Args=@(
        "--position",$Pos,"--path",$Worktree,"--log-file",$Log,"--",
        "--network-mvp",
        "--role=game-client",
        "--world=earth",
        "--server-address=127.0.0.1",
        "--server-port=$ServerPort",
        "--player-identity=$lower",
        "--node-id=live3-client-$lower-$Ordinal",
        "--network-debug",
        "--network-debug-stay-open",
        "--automation-control",
        "--automation-control-port=$Port",
        "--automation-control-token=$Token",
        "--automation-control-output-dir=$Output"
    )
    $p=Start-Process -FilePath $GodotGui -ArgumentList $Args -WorkingDirectory $Worktree -Environment @{
        APPDATA=$Profile
        LOCALAPPDATA=$Profile
    } -PassThru
    Write-JsonLine ([ordered]@{
        at=(Get-Date).ToString("o")
        event="CLIENT_STARTED"
        client=$Client
        ordinal=$Ordinal
        pid=$p.Id
        automation_port=$Port
    }) $ActionLog
    return [ordered]@{process=$p;log=$Log;profile=$Profile}
}

function Resolve-EarthResourcePlanarTarget {
    param([Parameter(Mandatory=$true)][string]$ResourceNodeId)

    $earthPath=Join-Path $Worktree "config\planets\earth.json"
    $resourcePath=Join-Path $Worktree "config\resources\v0_resource_nodes.json"
    if(-not(Test-Path $earthPath)){throw "EARTH_CONFIG_MISSING:$earthPath"}
    if(-not(Test-Path $resourcePath)){throw "RESOURCE_CONFIG_MISSING:$resourcePath"}

    $earth=Get-Content $earthPath -Raw | ConvertFrom-Json
    $catalog=Get-Content $resourcePath -Raw | ConvertFrom-Json
    $node=@($catalog.nodes | Where-Object {
        [string]$_.resource_node_id -eq $ResourceNodeId
    } | Select-Object -First 1)
    if($node.Count -ne 1){throw "RESOURCE_NODE_NOT_FOUND:$ResourceNodeId"}
    $spatial=$node[0].spatial
    if([string]$spatial.frame -ne "earth-fixed"){
        throw "RESOURCE_NODE_FRAME_UNSUPPORTED:${ResourceNodeId}:$($spatial.frame)"
    }

    # Mirror EarthResourceSpatialResolver exactly. Note that the accepted
    # resolver defines east as UP x anchor; for increasing longitude at the
    # canonical spawn this produces a negative planar X.
    $deg=[math]::PI/180.0
    $spawn=$earth.default_spawn
    $lat0=[double]$spawn.latitude_deg*$deg
    $lon0=[double]$spawn.longitude_deg*$deg
    $lat1=[double]$spatial.latitude_deg*$deg
    $lon1=[double]$spatial.longitude_deg*$deg

    $anchorVector=@(
        [math]::Cos($lat0)*[math]::Cos($lon0),
        [math]::Sin($lat0),
        [math]::Cos($lat0)*[math]::Sin($lon0)
    )
    $targetVector=@(
        [math]::Cos($lat1)*[math]::Cos($lon1),
        [math]::Sin($lat1),
        [math]::Cos($lat1)*[math]::Sin($lon1)
    )
    $east=@($anchorVector[2],0.0,-$anchorVector[0])
    $eastLength=[math]::Sqrt(
        $east[0]*$east[0]+$east[1]*$east[1]+$east[2]*$east[2]
    )
    if($eastLength-le0.000001){throw "RESOURCE_EAST_AXIS_INVALID"}
    $east=@($east[0]/$eastLength,$east[1]/$eastLength,$east[2]/$eastLength)

    $north=@(
        $anchorVector[1]*$east[2]-$anchorVector[2]*$east[1],
        $anchorVector[2]*$east[0]-$anchorVector[0]*$east[2],
        $anchorVector[0]*$east[1]-$anchorVector[1]*$east[0]
    )
    $northLength=[math]::Sqrt(
        $north[0]*$north[0]+$north[1]*$north[1]+$north[2]*$north[2]
    )
    if($northLength-le0.000001){throw "RESOURCE_NORTH_AXIS_INVALID"}
    $north=@(
        $north[0]/$northLength,
        $north[1]/$northLength,
        $north[2]/$northLength
    )

    $radius=[double]$earth.radius_m
    $anchorRadius=$radius+[double]$spawn.altitude_m
    $targetRadius=$radius+[double]$spatial.altitude_m
    $dx=$targetVector[0]*$targetRadius-$anchorVector[0]*$anchorRadius
    $dy=$targetVector[1]*$targetRadius-$anchorVector[1]*$anchorRadius
    $dz=$targetVector[2]*$targetRadius-$anchorVector[2]*$anchorRadius

    return [ordered]@{
        resource_node_id=$ResourceNodeId
        x=$dx*$east[0]+$dy*$east[1]+$dz*$east[2]
        y=$dx*$anchorVector[0]+$dy*$anchorVector[1]+$dz*$anchorVector[2]
        z=-($dx*$north[0]+$dy*$north[1]+$dz*$north[2])
    }
}


function Drive-To {
    param(
        [ValidateSet("A","B")][string]$Client,
        [double]$TargetX,
        [double]$TargetZ,
        [double]$Radius=0.65,
        [int]$MaxAttempts=80
    )
    for($attempt=0;$attempt-lt$MaxAttempts;$attempt++){
        $state=Get-AutomationState $Client
        $pos=$state.local_player.position
        $x=[double]$pos.x
        $z=[double]$pos.z
        $dx=$TargetX-$x
        $dz=$TargetZ-$z
        $distance=[math]::Sqrt($dx*$dx+$dz*$dz)
        if($distance-le$Radius){
            Invoke-Control $Client @("stop") | Out-Null
            # A stop request first neutralizes the local automation intent, then
            # the authoritative fixed-tick/input path drains the last accepted
            # movement sample. Observe the settled server state instead of the
            # optimistic state returned by movement.stop.
            Start-Sleep -Milliseconds 450
            $settled=Get-AutomationState $Client
            $settledX=[double]$settled.local_player.position.x
            $settledZ=[double]$settled.local_player.position.z
            $settledDx=$TargetX-$settledX
            $settledDz=$TargetZ-$settledZ
            $settledDistance=[math]::Sqrt($settledDx*$settledDx+$settledDz*$settledDz)
            if($settledDistance-le($Radius+0.45)){
                return $settled
            }
            continue
        }
        $yaw=[math]::Atan2(-$dx,-$dz)
        # Full-speed 700 ms pulses are appropriate in open space, but close to
        # a small interaction target they can cross the focus cone before the
        # stop reaches authoritative simulation. Taper both input magnitude and
        # TTL while preserving the normal prediction -> transport -> server path.
        $throttle=[math]::Min(1.0,[math]::Max(0.20,$distance/4.0))
        $ttlMs=700
        $sleepMs=280
        if($distance-lt4.0){
            $ttlMs=240
            $sleepMs=160
        }
        if($distance-lt1.5){
            $ttlMs=140
            $sleepMs=120
        }
        Invoke-Control $Client @(
            "move","--z",
            $throttle.ToString([cultureinfo]::InvariantCulture),
            "--yaw",$yaw.ToString([cultureinfo]::InvariantCulture),
            "--ttl-ms",$ttlMs.ToString([cultureinfo]::InvariantCulture)
        ) | Out-Null
        Start-Sleep -Milliseconds $sleepMs
    }
    Invoke-Control $Client @("stop") -AllowFailure | Out-Null
    throw "MOVE_TARGET_NOT_REACHED:$($Client):$TargetX,$TargetZ"
}

function Assert-Converged {
    param($A,$B,[string]$Label)
    foreach($field in @("item_graph_checksum","resource_checksum")){
        if([string]$A.$field -ne [string]$B.$field){
            throw "CONVERGENCE_MISMATCH:$($Label):$field"
        }
    }
    $aConstruct=($A.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
    $bConstruct=($B.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
    if($aConstruct-ne$bConstruct){throw "CONVERGENCE_MISMATCH:$($Label):construction"}
}

function Wait-ConvergedStates {
    param([int]$TimeoutSeconds=25,[string]$Label="convergence")
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    $lastError=""
    while((Get-Date)-lt$deadline){
        try{
            $a=Get-AutomationState A
            $b=Get-AutomationState B
            Assert-Converged $a $b $Label
            return [ordered]@{a=$a;b=$b}
        }catch{
            $lastError=$_.Exception.Message
        }
        Start-Sleep -Milliseconds 350
    }
    throw "CONVERGENCE_TIMEOUT:$($Label):$lastError"
}

function Assert-StableRecovery {
    param($Before,$After,[string]$Label)
    foreach($field in @("item_graph_checksum","resource_checksum")){
        if([string]$Before.$field -ne [string]$After.$field){
            throw "RECOVERY_MISMATCH:$($Label):$field"
        }
    }
    $beforeConstruct=($Before.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
    $afterConstruct=($After.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
    if($beforeConstruct-ne$afterConstruct){throw "RECOVERY_MISMATCH:$($Label):construction"}
    if([string]$Before.player_entity_id -ne [string]$After.player_entity_id){
        throw "RECOVERY_PLAYER_ENTITY_MISMATCH:$Label"
    }
    foreach($axis in @("x","y","z")){
        $beforeValue=[double]$Before.local_player.position.$axis
        $afterValue=[double]$After.local_player.position.$axis
        if([math]::Abs($beforeValue-$afterValue)-gt0.001){
            throw "RECOVERY_PLAYER_POSITION_MISMATCH:$($Label):$($axis):$($beforeValue):$($afterValue)"
        }
    }
}

function Wait-StatePredicate {
    param(
        [ValidateSet("A","B")][string]$Client,
        [scriptblock]$Predicate,
        [int]$TimeoutSeconds=20,
        [string]$ErrorCode="STATE_PREDICATE_TIMEOUT"
    )
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt$deadline){
        $s=Get-AutomationState $Client
        if(& $Predicate $s){return $s}
        Start-Sleep -Milliseconds 300
    }
    throw "$($ErrorCode):$($Client)"
}

try {
    [ordered]@{
        schema="dws.live3.product_recovery_session.v1"
        product_head=$ProductHead
        product_tree=$ProductTree
        worktree=$Worktree
        session=$SessionRoot
        persistence_root=$PersistenceRoot
        server_port=$ServerPort
        created_at=(Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $SessionRoot "session.json") -Encoding UTF8

    $serverLifetimeMs=$PhaseOneServerLifetimeSeconds*1000
    $Processes.server1=Start-Live3Server -Ordinal 1 -ShutdownAfterMs $serverLifetimeMs
    $Processes.a1=Start-Live3Client -Client A -Ordinal 1
    $Processes.b=Start-Live3Client -Client B -Ordinal 1
    Wait-Bridge A
    Wait-Bridge B
    Wait-ConnectionState A | Out-Null
    Wait-ConnectionState B | Out-Null
    $baselinePair=Wait-ConvergedStates 25 "baseline"
    $baselineA=$baselinePair.a
    $baselineB=$baselinePair.b
    $Observations.baseline_a=$baselineA
    $Observations.baseline_b=$baselineB

    $hotbar=Invoke-Control A @("command","inventory.hotbar.select 2")
    if($null-eq$hotbar -or -not [bool]$hotbar.ok){throw "HOTBAR_MUTATION_FAILED"}
    Wait-AsyncIdle A
    $afterHotbar=Wait-StatePredicate A {
        param($s)
        return [string]$s.item_graph_checksum -ne [string]$baselineA.item_graph_checksum
    } 15 "ITEM_GRAPH_DID_NOT_MUTATE"
    $Observations.after_hotbar=$afterHotbar

    $oreTarget=Resolve-EarthResourcePlanarTarget "resource/earth/ore-demo/1"
    $nearOre=Get-AutomationState A
    $oreDx=[double]$oreTarget.x-[double]$nearOre.local_player.position.x
    $oreDz=[double]$oreTarget.z-[double]$nearOre.local_player.position.z
    $oreHorizontal=[math]::Sqrt($oreDx*$oreDx+$oreDz*$oreDz)

    # Spawn A is normally already within the five-metre P1 interaction range.
    # If a future spawn/persistence state is farther away, approach from the
    # current side and stop at a bounded 3.2 m standoff instead of hard-coding
    # a world coordinate.
    if($oreHorizontal-gt3.8){
        $standoff=3.2
        $approachX=[double]$oreTarget.x-($oreDx/$oreHorizontal)*$standoff
        $approachZ=[double]$oreTarget.z-($oreDz/$oreHorizontal)*$standoff
        $nearOre=Drive-To A $approachX $approachZ 0.55 80
        $oreDx=[double]$oreTarget.x-[double]$nearOre.local_player.position.x
        $oreDz=[double]$oreTarget.z-[double]$nearOre.local_player.position.z
        $oreHorizontal=[math]::Sqrt($oreDx*$oreDx+$oreDz*$oreDz)
    }
    if($oreHorizontal-lt0.001){throw "RESOURCE_AIM_HORIZONTAL_DISTANCE_INVALID"}

    # Aim at the actual projected resource centre through the normal product
    # camera path. ResourceMiningTarget adds +0.52 m over the tangent surface;
    # the playable camera is 1.75 m above it at ground level.
    $aimYaw=[math]::Atan2(-$oreDx,-$oreDz)
    $targetPresentationY=[double]$oreTarget.y+0.52
    $eyePresentationY=1.75+[double]$nearOre.local_player.position.y
    $aimPitch=[math]::Atan2(
        $targetPresentationY-$eyePresentationY,
        $oreHorizontal
    )
    $Observations.ore_target=$oreTarget
    $Observations.near_ore=$nearOre
    Invoke-Control A @(
        "view",
        "--yaw",$aimYaw.ToString([cultureinfo]::InvariantCulture),
        "--pitch",$aimPitch.ToString([cultureinfo]::InvariantCulture)
    ) | Out-Null
    $equip=Invoke-Control A @("command","tool.mining.equip")
    if($null-eq$equip -or -not [bool]$equip.ok){throw "MINING_TOOL_EQUIP_FAILED"}
    Wait-AsyncIdle A
    $beforeMine=Get-AutomationState A

    for($i=0;$i-lt2;$i++){
        $mine=Invoke-Control A @("command","player.interact")
        if($null-eq$mine -or -not [bool]$mine.ok){throw "PRODUCT_MINE_COMMAND_FAILED:$i"}
        Wait-AsyncIdle A 25
        $expected=[int]$beforeMine.resource_generation+$i+1
        Wait-StatePredicate A {
            param($s)
            return [int]$s.resource_generation -ge $expected
        } 20 "RESOURCE_GENERATION_DID_NOT_ADVANCE" | Out-Null
    }
    $afterMine=Get-AutomationState A
    if([string]$afterMine.resource_checksum -eq [string]$beforeMine.resource_checksum){
        throw "RESOURCE_CHECKSUM_DID_NOT_CHANGE"
    }
    $Observations.after_mine=$afterMine

    $beforeBuild=Get-AutomationState A
    $build=Invoke-Control A @("command","construction.build.next")
    if($null-eq$build -or -not [bool]$build.ok){throw "CONSTRUCTION_BUILD_SEND_FAILED"}
    Wait-AsyncIdle A 30
    $afterBuild=Wait-StatePredicate A {
        param($s)
        $beforeJson=($beforeBuild.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
        $afterJson=($s.construction_construct_checksums | ConvertTo-Json -Depth 20 -Compress)
        return $afterJson -ne $beforeJson -and $afterJson -ne "{}"
    } 25 "CONSTRUCTION_DID_NOT_MUTATE"
    $Observations.after_build=$afterBuild

    Invoke-Control A @("stop") | Out-Null
    Start-Sleep -Seconds 3
    $preClientPair=Wait-ConvergedStates 20 "pre-client-restart"
    $preClientRestartA=$preClientPair.a
    $preClientRestartB=$preClientPair.b
    $Observations.pre_client_restart_a=$preClientRestartA
    $Observations.pre_client_restart_b=$preClientRestartB

    Invoke-Control A @("command","app.quit") -AllowFailure | Out-Null
    $Processes.a1.process.WaitForExit(15000) | Out-Null
    if(-not $Processes.a1.process.HasExited){throw "CLIENT_A_DID_NOT_EXIT_CLEANLY"}

    $bDuringARestart=Wait-ConnectionState B @("CONNECTED") 15
    $Processes.a2=Start-Live3Client -Client A -Ordinal 2
    Wait-Bridge A
    Wait-ConnectionState A @("CONNECTED") 60 | Out-Null
    Wait-ConnectionState B @("CONNECTED") 20 | Out-Null
    $a2Pair=Wait-ConvergedStates 25 "client-a-restart"
    $a2=$a2Pair.a
    $bAfterA2=$a2Pair.b
    Assert-StableRecovery $preClientRestartA $a2 "client-a-restart"
    $Observations.client_a_restart=$a2
    $Observations.client_b_survived_a_restart=$bAfterA2

    Start-Sleep -Seconds 2
    $preServerPair=Wait-ConvergedStates 20 "pre-server-restart"
    $preServerA=$preServerPair.a
    $preServerB=$preServerPair.b
    $Observations.pre_server_restart_a=$preServerA
    $Observations.pre_server_restart_b=$preServerB

    $plannedDeadline=(Get-Date).AddSeconds($PhaseOneServerLifetimeSeconds+35)
    while((Get-Date)-lt$plannedDeadline){
        $ep=Get-NetUDPEndpoint -LocalPort $ServerPort -ErrorAction SilentlyContinue
        if($null-eq$ep){break}
        Start-Sleep -Milliseconds 500
    }
    Wait-PortFree -Port $ServerPort -TimeoutSeconds 5

    $outageA=Wait-ConnectionState A @("DISCONNECTED","RECONNECTING","CONNECTING") 30
    $outageB=Wait-ConnectionState B @("DISCONNECTED","RECONNECTING","CONNECTING") 30
    $Observations.server_outage_a=$outageA
    $Observations.server_outage_b=$outageB

    $Processes.server2=Start-Live3Server -Ordinal 2
    Wait-ConnectionState A @("CONNECTED") 75 | Out-Null
    Wait-ConnectionState B @("CONNECTED") 75 | Out-Null
    Start-Sleep -Seconds 2
    $postPair=Wait-ConvergedStates 30 "post-server-restart"
    $postA=$postPair.a
    $postB=$postPair.b
    Assert-StableRecovery $preServerA $postA "server-restart-a"
    Assert-StableRecovery $preServerB $postB "server-restart-b"
    $Observations.post_server_restart_a=$postA
    $Observations.post_server_restart_b=$postB

    $jitterBefore=Get-JitterState B
    $remoteBefore=0
    if($null-ne$jitterBefore.remotes.a){
        $remoteBefore=[int]$jitterBefore.remotes.a.accepted_presenter_samples
    }
    $x0=[double]$postA.local_player.position.x
    $z0=[double]$postA.local_player.position.z
    Drive-To A ($x0+1.5) $z0 0.45 60 | Out-Null
    Start-Sleep -Seconds 2
    $continuedA=Get-AutomationState A
    $jitterAfter=Get-JitterState B
    $dx=[double]$continuedA.local_player.position.x-$x0
    $dz=[double]$continuedA.local_player.position.z-$z0
    $moved=[math]::Sqrt($dx*$dx+$dz*$dz)
    if($moved-lt0.5){throw "POST_RESTART_MOVEMENT_NOT_OBSERVED:$moved"}
    if($null-eq$jitterAfter.remotes.a){throw "POST_RESTART_REMOTE_A_MISSING"}
    $remoteAfter=[int]$jitterAfter.remotes.a.accepted_presenter_samples
    if($remoteAfter-le$remoteBefore){throw "POST_RESTART_REMOTE_STREAM_DID_NOT_ADVANCE"}
    if([string]$jitterAfter.remotes.a.snapshot_clock_source -ne "CANONICAL_SNAPSHOT_CONTEXT"){
        throw "POST_RESTART_NON_CANONICAL_SNAPSHOT_CLOCK"
    }
    $Observations.post_restart_continuation=[ordered]@{
        movement_distance_m=$moved
        remote_samples_before=$remoteBefore
        remote_samples_after=$remoteAfter
        remote_mode=[string]$jitterAfter.remotes.a.mode
        snapshot_clock_source=[string]$jitterAfter.remotes.a.snapshot_clock_source
    }

    $server2Log=Get-Content $Processes.server2.log -Raw
    if($server2Log -notmatch '"recovered":true'){
        throw "SERVER2_RECOVERY_MARKER_MISSING"
    }
    if($server2Log -match 'SCRIPT ERROR:|Parse Error:|Compile Error:'){
        throw "SERVER2_SCRIPT_ERROR"
    }

    $Outcome="PASS"
}
catch {
    $Outcome="FAIL"
    $Failure=$_.Exception.Message
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString("o");event="LIVE3_FAILURE";error=$Failure}) $ActionLog
}
finally {
    foreach($Client in @("A","B")){
        try{Invoke-Control $Client @("stop") -AllowFailure | Out-Null}catch{}
        try{Invoke-Control $Client @("command","app.quit") -AllowFailure | Out-Null}catch{}
    }
    Start-Sleep -Seconds 2
    foreach($name in @("a1","a2","b")){
        if($Processes.Contains($name)){
            try{
                $p=$Processes[$name].process
                $p.Refresh()
                if(-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
            }catch{}
        }
    }
    foreach($name in @("server1","server2")){
        if($Processes.Contains($name)){
            try{
                $p=$Processes[$name].wrapper
                $p.Refresh()
                if(-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
            }catch{}
            try{
                $owner=[int]$Processes[$name].owner_pid
                if($owner-gt0){Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue}
            }catch{}
        }
    }

    $remaining=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" })
    [ordered]@{
        schema="dws.live3.product_recovery_report.v1"
        outcome=$Outcome
        failure=$Failure
        product_head=$ProductHead
        product_tree=$ProductTree
        session=$SessionRoot
        persistence_root=$PersistenceRoot
        observations=$Observations
        remaining_godot_pids=@($remaining | Select-Object -ExpandProperty Id)
        udp_port_free=($null-eq(Get-NetUDPEndpoint -LocalPort $ServerPort -ErrorAction SilentlyContinue))
        completed_at=(Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 80 | Set-Content $ReportPath -Encoding UTF8
}

Write-Host "LIVE3_PRODUCT_RECOVERY=$Outcome"
Write-Host "SESSION=$SessionRoot"
Write-Host "REPORT=$ReportPath"
if($Outcome-ne"PASS"){throw "LIVE3_PRODUCT_RECOVERY_FAILED:$Failure"}
