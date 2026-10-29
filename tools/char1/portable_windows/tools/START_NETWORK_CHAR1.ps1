[CmdletBinding()]
param([string]$GodotConsole='', [string]$AssetSource='', [switch]$SkipImport)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Playtest-Common.ps1')
$package=Get-CHAR1Root
$project=Join-Path $package 'project'
$info=Assert-CHAR1Snapshot $package
$godot=Resolve-CHAR1Godot $GodotConsole
Assert-PlaytestAssets -Package $package -GodotConsole $godot.Console -AssetSource $AssetSource -SkipImport:$SkipImport
$quoted='"{0}"' -f $project
$launchArguments=@('--max-fps','60','--disable-vsync','--rendering-driver','opengl3','--path',$quoted,'--','--product-shell')
$evidence=Join-Path $package 'evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$process=Start-PlaytestProcess -Executable $godot.GUI -Package $package -Role launcher -Identity 'launcher' -LaunchArguments $launchArguments -LogPrefix (Join-Path $evidence ('shell-'+(Get-Date -Format 'yyyyMMdd-HHmmss')))
[ordered]@{product_head=$info.product_head;product_tree=$info.product_tree;profile='PLAYTEST_R1_SAFE60';entrypoint='EARTH_PRODUCT_SHELL';ui_pid=$process.Id;gui_acceptance='PENDING';started=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $evidence 'playtest-launch.json') -Encoding UTF8
Write-Host 'DWS Playtest R1: Host World / Join World. No M7 playground.' -ForegroundColor Green
Write-Host 'For Host: use a new slot for a new world; Continue retains that world.'
Write-Host 'For Join: enter host IP, same port, and a DIFFERENT player name.'
Write-Host 'V/F7 toggles camera; the yellow hint gives direction/distance to your peer.'
