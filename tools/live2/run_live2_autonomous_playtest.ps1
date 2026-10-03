param(
    [Parameter(Mandatory = $true)][string]$Worktree,
    [string]$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [int]$ServerPort = 24580,
    [int]$ClientAPort = 27651,
    [int]$ClientBPort = 27652,
    [int]$MovementPhaseSeconds = 20,
    [string]$SessionRoot = "",
    [switch]$SkipGameplayActions
)

$ErrorActionPreference = "Stop"
$Worktree = (Resolve-Path $Worktree).Path
$ProductHead = (git -C $Worktree rev-parse HEAD).Trim()
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $SessionRoot = Join-Path $Worktree "artifacts\live2-r3-4-autonomous\$Stamp"
}
New-Item -ItemType Directory -Force $SessionRoot | Out-Null
$SessionRoot = (Resolve-Path $SessionRoot).Path
$Cli = Join-Path $Worktree "tools\live2\live2_automation_client.py"
$Analyzer = Join-Path $Worktree "tools\live2\analyze_live2_autonomous_playtest.py"
$SamplerScript = Join-Path $Worktree "tools\live2\watch_live2_server_stall.ps1"
if (-not (Test-Path $Cli)) { throw "AUTOMATION_CLI_NOT_FOUND:$Cli" }
if (-not (Test-Path $Analyzer)) { throw "AUTOMATION_ANALYZER_NOT_FOUND:$Analyzer" }
if (-not (Test-Path $SamplerScript)) { throw "SERVER_SAMPLER_NOT_FOUND:$SamplerScript" }
foreach ($binary in @($GodotGui, $GodotConsole)) {
    if (-not (Test-Path $binary)) { throw "GODOT_NOT_FOUND:$binary" }
}
$Foreign = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "godot*" })
if ($Foreign.Count -gt 0) {
    throw "FOREIGN_GODOT_PROCESS:$((($Foreign | Select-Object -ExpandProperty Id) -join ','))"
}

$Token = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))
$Profiles = Join-Path $SessionRoot "profiles"
$ServerProfile = Join-Path $Profiles "server"
$ClientAProfile = Join-Path $Profiles "client-a"
$ClientBProfile = Join-Path $Profiles "client-b"
$AutomationA = Join-Path $SessionRoot "automation-a"
$AutomationB = Join-Path $SessionRoot "automation-b"
foreach ($dir in @($ServerProfile,$ClientAProfile,$ClientBProfile,$AutomationA,$AutomationB)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
}

$ServerLog = Join-Path $SessionRoot "server.log"
$ClientALog = Join-Path $SessionRoot "client-a.log"
$ClientBLog = Join-Path $SessionRoot "client-b.log"
$ActionLog = Join-Path $SessionRoot "automation-actions.jsonl"
$JitterLog = Join-Path $SessionRoot "jitter-samples.jsonl"
$ReportPath = Join-Path $SessionRoot "AUTONOMOUS-PLAYTEST-REPORT.json"
$SamplerLog = Join-Path $SessionRoot "server-process-sampler.jsonl"
$Processes = [ordered]@{}
$GameplayResults = @()
$Outcome = "UNKNOWN"
$Failure = ""

function Write-JsonLine {
    param($Value,[string]$Path)
    ($Value | ConvertTo-Json -Depth 40 -Compress) | Add-Content -Path $Path -Encoding UTF8
}

function Invoke-Control {
    param([ValidateSet("A","B")][string]$Client,[string[]]$Arguments,[switch]$AllowFailure)
    $Port = if ($Client -eq "A") { $ClientAPort } else { $ClientBPort }
    $Output = & python $Cli --port $Port --token $Token @Arguments 2>&1 | Out-String
    $Code = $LASTEXITCODE
    $Parsed = $null
    try { $Parsed = $Output | ConvertFrom-Json -Depth 60 } catch {}
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString("o");client=$Client;arguments=$Arguments;exit_code=$Code;response=$Parsed;raw=if($null -eq $Parsed){$Output.Trim()}else{$null}}) $ActionLog
    if ($Code -ne 0 -and -not $AllowFailure) { throw "AUTOMATION_COMMAND_FAILED:${Client}:$($Arguments -join ' '):$Output" }
    return $Parsed
}

function Wait-Ready {
    param([ValidateSet("A","B")][string]$Client,[int]$TimeoutSeconds=45)
    $Deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt $Deadline){
        try {
            $Ping=Invoke-Control $Client @("ping") -AllowFailure
            if($null-ne $Ping -and [bool]$Ping.ok){ return }
        } catch {}
        Start-Sleep -Milliseconds 400
    }
    throw "AUTOMATION_BRIDGE_TIMEOUT:$Client"
}

function Wait-Connected {
    param([ValidateSet("A","B")][string]$Client,[int]$TimeoutSeconds=45)
    $Deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt $Deadline){
        try {
            $State=Invoke-Control $Client @("state","--kind","automation")
            if([string]$State.result.automation.connection_state -eq "CONNECTED"){ return }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    throw "CLIENT_CONNECT_TIMEOUT:$Client"
}

function Save-Jitter {
    param([ValidateSet("A","B")][string]$Client,[string]$Label)
    $State=Invoke-Control $Client @("state","--kind","jitter")
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString("o");label=$Label;client=$Client;jitter=$State.result.jitter}) $JitterLog
    return $State
}

function Capture {
    param([ValidateSet("A","B")][string]$Client,[string]$Name)
    Invoke-Control $Client @("screenshot","--filename",$Name) -AllowFailure | Out-Null
}

function Drive {
    param([ValidateSet("A","B")][string]$Client,[double]$X,[double]$Z,[double]$Yaw,[bool]$Sprint,[int]$Seconds,[string]$Label)
    $Deadline=(Get-Date).AddSeconds($Seconds)
    $NextSample=Get-Date
    while((Get-Date)-lt $Deadline){
        $Args=@("move","--x",$X.ToString([cultureinfo]::InvariantCulture),"--z",$Z.ToString([cultureinfo]::InvariantCulture),"--yaw",$Yaw.ToString([cultureinfo]::InvariantCulture),"--ttl-ms","900")
        if($Sprint){$Args+="--sprint"}
        Invoke-Control $Client $Args | Out-Null
        if((Get-Date)-ge $NextSample){
            Save-Jitter "A" "$Label-A" | Out-Null
            Save-Jitter "B" "$Label-B" | Out-Null
            $NextSample=(Get-Date).AddSeconds(2)
        }
        Start-Sleep -Milliseconds 450
    }
    Invoke-Control $Client @("stop") | Out-Null
}

function Gameplay {
    param([ValidateSet("A","B")][string]$Client,[string]$Line,[string]$Label)
    $BeforeA=Save-Jitter "A" "$Label-before-A"
    $BeforeB=Save-Jitter "B" "$Label-before-B"
    $Result=Invoke-Control $Client @("command",$Line) -AllowFailure
    Start-Sleep -Milliseconds 1200
    $AfterA=Save-Jitter "A" "$Label-after-A"
    $AfterB=Save-Jitter "B" "$Label-after-B"
    Capture $Client "$Label-$Client.png"
    return [ordered]@{label=$Label;client=$Client;command=$Line;response=$Result;before_a=$BeforeA.result.jitter;before_b=$BeforeB.result.jitter;after_a=$AfterA.result.jitter;after_b=$AfterB.result.jitter}
}

try {
    [ordered]@{schema="dws.live2.r3_4.autonomous_session.v1";product_head=$ProductHead;worktree=$Worktree;session=$SessionRoot;server_port=$ServerPort;client_a_port=$ClientAPort;client_b_port=$ClientBPort;created_at=(Get-Date).ToString("o")} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $SessionRoot "session.json") -Encoding UTF8

    $ServerArgs=@("--headless","--path",$Worktree,"--log-file",$ServerLog,"--","--network-mvp","--role=dedicated-server","--world=earth","--server-address=127.0.0.1","--server-port=$ServerPort","--node-id=live2-r3-4-auto-server","--network-debug")
    $Processes.server=Start-Process -FilePath $GodotConsole -ArgumentList $ServerArgs -WorkingDirectory $Worktree -Environment @{APPDATA=$ServerProfile;LOCALAPPDATA=$ServerProfile} -PassThru
    Start-Sleep -Seconds 2
    if($Processes.server.HasExited){throw "SERVER_EXITED_EARLY:$($Processes.server.ExitCode)"}
    $Processes.sampler=Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile","-File",$SamplerScript,"-ProcessId","$($Processes.server.Id)","-Port","$ServerPort","-OutputPath",$SamplerLog,"-ServerLog",$ServerLog,"-IntervalMs","500") -WorkingDirectory $Worktree -PassThru

    $Common=@("--path",$Worktree,"--resolution","900x650","--","--network-mvp","--role=game-client","--world=earth","--server-address=127.0.0.1","--server-port=$ServerPort","--network-debug","--network-debug-stay-open","--automation-control","--automation-control-token=$Token")
    $ArgsA=@("--position","20,50","--log-file",$ClientALog)+$Common+@("--player-identity=a","--node-id=live2-r3-4-auto-a","--automation-control-port=$ClientAPort","--automation-control-output-dir=$AutomationA")
    $ArgsB=@("--position","960,50","--log-file",$ClientBLog)+$Common+@("--player-identity=b","--node-id=live2-r3-4-auto-b","--automation-control-port=$ClientBPort","--automation-control-output-dir=$AutomationB")
    $Processes.a=Start-Process -FilePath $GodotGui -ArgumentList $ArgsA -WorkingDirectory $Worktree -Environment @{APPDATA=$ClientAProfile;LOCALAPPDATA=$ClientAProfile} -PassThru
    $Processes.b=Start-Process -FilePath $GodotGui -ArgumentList $ArgsB -WorkingDirectory $Worktree -Environment @{APPDATA=$ClientBProfile;LOCALAPPDATA=$ClientBProfile} -PassThru

    Wait-Ready "A"; Wait-Ready "B"; Wait-Connected "A"; Wait-Connected "B"
    Capture "A" "00-baseline-a.png"; Capture "B" "00-baseline-b.png"
    Save-Jitter "A" "baseline-A" | Out-Null; Save-Jitter "B" "baseline-B" | Out-Null

    Drive "A" 0 -1 0 $true $MovementPhaseSeconds "A-forward"
    Capture "A" "10-after-a-move-a.png"; Capture "B" "10-after-a-move-b.png"
    Drive "B" 0 -1 0.75 $true $MovementPhaseSeconds "B-forward"
    Capture "A" "20-after-b-move-a.png"; Capture "B" "20-after-b-move-b.png"
    Drive "A" 0.8 -0.6 1.2 $false ([math]::Max(8,[int]($MovementPhaseSeconds/2))) "A-zig"
    Drive "B" -0.8 -0.6 -1.0 $false ([math]::Max(8,[int]($MovementPhaseSeconds/2))) "B-zig"

    if(-not $SkipGameplayActions){
        foreach($Spec in @(
            @{Client="A";Line="player.interact";Label="30-interact"},
            @{Client="A";Line="tool.mining.equip";Label="31-equip"},
            @{Client="A";Line="inventory.hotbar.select 1";Label="32-hotbar1"},
            @{Client="A";Line="construction.mode.toggle";Label="33-buildmode"},
            @{Client="A";Line="player.primary";Label="34-primary"},
            @{Client="A";Line="construction.build.next";Label="35-construction"}
        )){$GameplayResults+=Gameplay $Spec.Client $Spec.Line $Spec.Label}

        Invoke-Control "A" @("key","TAB") -AllowFailure | Out-Null; Start-Sleep -Milliseconds 250
        Invoke-Control "A" @("key","TAB","--up") -AllowFailure | Out-Null; Capture "A" "40-inventory.png"
        Invoke-Control "A" @("key","G") -AllowFailure | Out-Null; Invoke-Control "A" @("key","G","--up") -AllowFailure | Out-Null; Start-Sleep -Milliseconds 400; Capture "A" "41-after-g.png"
        Invoke-Control "A" @("key","ESC") -AllowFailure | Out-Null; Invoke-Control "A" @("key","ESC","--up") -AllowFailure | Out-Null; Start-Sleep -Milliseconds 400; Capture "A" "42-after-esc.png"

        $GameplayResults+=Gameplay "A" "network.reconnect" "50-reconnect"
        Wait-Connected "A" 45
        Drive "A" 0 -1 0.4 $false 8 "A-post-reconnect"
    }

    Save-Jitter "A" "final-A" | Out-Null; Save-Jitter "B" "final-B" | Out-Null
    Capture "A" "99-final-a.png"; Capture "B" "99-final-b.png"
    $Outcome="COMPLETED"
} catch {
    $Outcome="FAILED"; $Failure=$_.Exception.Message
    Write-JsonLine ([ordered]@{at=(Get-Date).ToString("o");event="AUTONOMOUS_PLAYTEST_FAILURE";error=$Failure}) $ActionLog
} finally {
    foreach($Client in @("A","B")){try{Invoke-Control $Client @("stop") -AllowFailure | Out-Null}catch{}}
    foreach($Client in @("A","B")){try{Invoke-Control $Client @("command","app.quit") -AllowFailure | Out-Null}catch{}}
    Start-Sleep -Seconds 2
    foreach($Name in @("a","b","sampler","server")){
        if($Processes.Contains($Name)){
            try{$P=$Processes[$Name];$P.Refresh();if(-not $P.HasExited){Stop-Process -Id $P.Id -Force -ErrorAction SilentlyContinue}}catch{}
        }
    }
    [ordered]@{schema="dws.live2.r3_4.autonomous_report.v1";outcome=$Outcome;failure=$Failure;product_head=$ProductHead;session=$SessionRoot;movement_phase_seconds=$MovementPhaseSeconds;gameplay_actions=$GameplayResults;action_log=$ActionLog;jitter_log=$JitterLog;sampler_log=$SamplerLog;automation_a=$AutomationA;automation_b=$AutomationB;server_log=$ServerLog;client_a_log=$ClientALog;client_b_log=$ClientBLog;completed_at=(Get-Date).ToString("o")} | ConvertTo-Json -Depth 60 | Set-Content $ReportPath -Encoding UTF8
    try { & python $Analyzer $SessionRoot | Set-Content (Join-Path $SessionRoot "analysis-console.txt") -Encoding UTF8 } catch { Write-Warning "AUTONOMOUS_ANALYZER_FAILED:$($_.Exception.Message)" }
}

Write-Host "LIVE2_R3_4_AUTONOMOUS_RESULT=$Outcome"
Write-Host "SESSION=$SessionRoot"
Write-Host "REPORT=$ReportPath"
if($Outcome -ne "COMPLETED"){throw "AUTONOMOUS_PLAYTEST_FAILED:$Failure"}