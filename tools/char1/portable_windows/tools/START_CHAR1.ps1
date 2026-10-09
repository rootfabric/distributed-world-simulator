[CmdletBinding()]
param(
    [string] $GodotConsole = '',
    [string] $AssetSource = '',
    [switch] $SkipImport
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CHAR1-Common.ps1')
$package = Get-CHAR1Root
$project = Join-Path $package 'project'
$info = Assert-CHAR1Snapshot $package
$godot = Resolve-CHAR1Godot $GodotConsole
$assetRoot = Ensure-CHAR1RealAssets $package $AssetSource
if (-not $SkipImport) {
    [void](Invoke-CHAR1Command $godot.Console $project @('--headless','--editor','--import','--quit') 'cold-import')
}
$scene = 'res://scenes/labs/character/char1_realistic_avatar_viewer.tscn'
$arguments = @('--rendering-driver','opengl3','--path',('"{0}"' -f $project),$scene)
$process = Start-Process -FilePath $godot.GUI -ArgumentList $arguments -WorkingDirectory $project -PassThru
$record = [ordered]@{
    product_head = $info.product_head
    product_tree = $info.product_tree
    preview_pid = $process.Id
    scene = $scene
    asset_root = $assetRoot
    startup_mode = 'THIRD_PERSON'
    first_person_body = 'HIDDEN'
    third_person_body = 'VISIBLE'
    launched_at = (Get-Date).ToString('o')
}
$evidence = Join-Path $package 'evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'preview-launch.json') -Encoding UTF8
Write-Host ('CHAR1 REALISTIC GUI STARTED - PID {0}' -f $process.Id) -ForegroundColor Green
Write-Host 'C/V: switch first-person (body HIDDEN) / third-person (body VISIBLE).'
Write-Host '1: real Quaternius; 2/3: procedural variants; I/W/R: animation; mouse orbit; wheel: zoom.'
Write-Host 'GUI stays open until you close it.'
