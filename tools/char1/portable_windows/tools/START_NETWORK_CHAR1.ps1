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
[void](Ensure-CHAR1RealAssets $package $AssetSource)
if (-not $SkipImport) {
    [void](Invoke-CHAR1Command $godot.Console $project @('--headless','--editor','--import','--quit') 'char2-product-shell-import')
}
# Real USER1 product shell: Host World starts a dedicated server and client A;
# Join World starts another *real* ENet GUI client B. This is not the avatar lab.
$argsList = @(
    '--rendering-driver', 'opengl3',
    '--path', ('"{0}"' -f $project),
    '--', '--product-shell'
)
$process = Start-Process -FilePath $godot.GUI -WorkingDirectory $project -ArgumentList $argsList -PassThru
$evidence = Join-Path $package 'evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
[ordered]@{
    product_head = $info.product_head
    product_tree = $info.product_tree
    mode = 'REAL_ENET_HOST_JOIN'
    ui_pid = $process.Id
    initial_view = 'FIRST_PERSON'
    local_first_person_body = 'HIDDEN'
    local_third_person_body = 'VISIBLE'
    remote_avatar_provider = 'avatar/quaternius'
    command = 'Host World -> player a, then Join World -> player b'
    launched_at = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'char2-product-shell-launch.json') -Encoding UTF8
Write-Host ('CHAR2 REAL NETWORK PRODUCT SHELL STARTED: PID {0}' -f $process.Id) -ForegroundColor Green
Write-Host 'Click Host World (player a, 24580), then Join World (127.0.0.1, player b, 24580).'
Write-Host 'In each client: V/F7 toggles first/third-person. The OTHER player always keeps the full Quaternius avatar.'
Write-Host 'F1 console: character.camera.status, character.avatar.status; no network protocol changes.'
Write-Host 'Windows remain open for user testing until the user closes them.'
