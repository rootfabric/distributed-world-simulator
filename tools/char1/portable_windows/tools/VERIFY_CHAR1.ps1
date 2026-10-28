[CmdletBinding()]
param(
    [string] $GodotConsole = '',
    [string] $AssetSource = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CHAR1-Common.ps1')
$package = Get-CHAR1Root
$project = Join-Path $package 'project'
$info = Assert-CHAR1Snapshot $package
$godot = Resolve-CHAR1Godot $GodotConsole
$assetRoot = Ensure-CHAR1RealAssets $package $AssetSource
[void](Invoke-CHAR1Command $godot.Console $project @('--headless','--editor','--import','--quit') 'cold-import')
$tests = @(
    'tests/characters/test_char1_production_avatar.gd',
    'tests/characters/test_char1_external_provider.gd',
    'tests/characters/test_char1_first_person_body_visibility.gd',
    'tests/runtime/test_v0_user1_product_seam_bridge.gd',
    'tests/runtime/test_v0_ux0_product_shell.gd'
)
$results = @()
foreach ($test in $tests) {
    $name = [IO.Path]::GetFileNameWithoutExtension($test)
    $log = Invoke-CHAR1Command $godot.Console $project @('--headless','--script',('res://' + $test)) $name 240
    if ($log -notmatch 'PASS\s*\(' -and $log -notmatch '0 failures') {
        throw ('CHAR1_TEST_MARKER_MISSING:{0}' -f $test)
    }
    $results += [ordered]@{ test=$test; result='PASS' }
    Write-Host ('PASS: {0}' -f $name) -ForegroundColor Green
}
# A real GUI renderer (not headless): the smoke must reject Quaternius fallback.
$visualTest = 'tests/characters/test_char1_realistic_viewmode.gd'
$log = Invoke-CHAR1Command $godot.Console $project @('--rendering-driver','opengl3','--script',('res://' + $visualTest)) 'viewmode-gui' 240
if ($log -notmatch 'CHAR1 VIEWMODE: PASS') { throw 'CHAR1_REAL_ASSET_GUI_VIEWMODE_FAILED' }
$images = @('viewmode-third-person.png','viewmode-first-person.png')
foreach ($image in $images) {
    $path = Join-Path (Join-Path $project 'artifacts\char1-viewmode') $image
    if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -lt 2048) {
        throw ('CHAR1_SCREENSHOT_MISSING:{0}' -f $image)
    }
}
$results += [ordered]@{ test=$visualTest; result='PASS' }
$evidence = Join-Path $package 'evidence'
$report = [ordered]@{
    product_head=$info.product_head
    product_tree=$info.product_tree
    godot_version=$godot.Version
    godot_sha256=$godot.Sha256
    quaternius_assets=$assetRoot
    independent_tests=$results
    viewmode='PASS'
    body_hidden_first_person='PASS'
    third_person_restored='PASS'
    portable_launcher_revision='PS51_EXITCODE_HANDLE_R2'
    result='PASS'
    checked_at=(Get-Date).ToString('o')
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'CHAR1_TEST_REPORT.json') -Encoding UTF8
Write-Host 'CHAR1 PORTABLE PREVIEW VERIFICATION: PASS' -ForegroundColor Green
