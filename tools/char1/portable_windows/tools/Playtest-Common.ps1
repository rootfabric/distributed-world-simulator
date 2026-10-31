# Shared launcher for Product Shell AND the two-client check: no playground.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CHAR1-Common.ps1')

function Start-PlaytestProcess {
    param(
        [Parameter(Mandatory=$true)][string]$Executable,
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][ValidateSet('server','client','launcher')][string]$Role,
        [string]$Identity = 'launcher',
        [Parameter(Mandatory=$true)][string[]]$LaunchArguments,
        [string]$LogPrefix = ''
    )
    $project = Join-Path $Package 'project'
    $info = Assert-CHAR1Snapshot $Package
    $profile = Get-Content -LiteralPath (Join-Path $project 'config/release/playtest-r1.json') -Raw | ConvertFrom-Json
    if($profile.id -ne 'PLAYTEST_R1_SAFE60'){throw 'PLAYTEST_PROFILE_MISMATCH'}
    $values = @{}
    # Strip fault injection and stale canary environment from previous tests.
    Get-ChildItem Env: | Where-Object {$_.Name -like 'DWS_NET_*'} | ForEach-Object {$values[$_.Name]=$null}
    foreach($prop in $profile.server_environment.PSObject.Properties){$values[$prop.Name]='0'}
    foreach($prop in $profile.client_environment.PSObject.Properties){$values[$prop.Name]='0'}
    foreach($name in $profile.disabled_environment){$values[$name]='0'}
    $flags=if($Role -eq 'server'){$profile.server_environment}elseif($Role -eq 'client'){$profile.client_environment}else{$null}
    if($null -ne $flags){foreach($prop in $flags.PSObject.Properties){$values[$prop.Name]=[string]$prop.Value}}
    $dataRoot=Join-Path $Package 'data'
    $root=Join-Path $dataRoot $Identity
    foreach($dir in @($root,(Join-Path $root 'data'),(Join-Path $root 'config'),(Join-Path $root 'cache'))){New-Item -ItemType Directory -Force $dir | Out-Null}
    $values['DWS_PLAYTEST_PROFILE']=$profile.id
    $values['DWS_PLAYTEST_SOURCE_HEAD']=$info.product_head
    $values['DWS_PLAYTEST_DATA_ROOT']=$dataRoot
    $values['HOME']=$root; $values['USERPROFILE']=$root
    $values['APPDATA']=(Join-Path $root 'data'); $values['LOCALAPPDATA']=$values['APPDATA']
    $values['XDG_DATA_HOME']=$values['APPDATA'];$values['XDG_CONFIG_HOME']=(Join-Path $root 'config');$values['XDG_CACHE_HOME']=(Join-Path $root 'cache')
    $values['BREAKPOINT_RUNTIME_DISABLED']='1';$values['GODOT_SILENCE_ROOT_WARNING']='1'
    $saved=@{}
    foreach($name in $values.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try {
        foreach($name in $values.Keys){[Environment]::SetEnvironmentVariable($name,$values[$name],'Process')}
        $params=@{FilePath=$Executable;ArgumentList=$LaunchArguments;WorkingDirectory=$project;PassThru=$true}
        if($LogPrefix){$params.RedirectStandardOutput=$LogPrefix+'.stdout.log';$params.RedirectStandardError=$LogPrefix+'.stderr.log'}
        $process=Start-Process @params
        $null=$process.Handle
        return $process
    } finally {
        foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    }
}

function Assert-PlaytestAssets {
    param([string]$Package,[string]$GodotConsole,[string]$AssetSource,[switch]$SkipImport)
    $project=Join-Path $Package 'project'
    [void](Ensure-CHAR1RealAssets $Package $AssetSource)
    if(-not $SkipImport){[void](Invoke-CHAR1Command $GodotConsole $project @('--headless','--editor','--import') 'playtest-cold-import')}
    [void](Invoke-CHAR1Command $GodotConsole $project @('--headless','--script','res://tests/characters/test_char1_embedded_quaternius_assets.gd') 'playtest-real-model')
    # The checked-in asset test rejects fallback and returns a nonzero code.
    # Invoke-CHAR1Command validates that actual exit code and script errors.
}
