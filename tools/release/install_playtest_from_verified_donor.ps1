[CmdletBinding()]
param(
    [string]$DonorZip='C:\dws-char2-playtest-r1-delivery\CHAR1_REALISTIC_WITH_AVATAR_d4ab2424_Windows.zip',
    [string]$Destination='',
    [switch]$Launch,
    [switch]$NoZip
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$meta=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RELEASE.json') -Raw|ConvertFrom-Json
$payload=Join-Path $PSScriptRoot 'playtest-r1-payload.zip'
if((Get-FileHash $payload -Algorithm SHA256).Hash.ToLowerInvariant() -ne $meta.payload_sha256){throw 'UPDATE_PAYLOAD_SHA_MISMATCH'}
if(-not(Test-Path -LiteralPath $DonorZip)){
    $near=Join-Path $PSScriptRoot 'CHAR1_REALISTIC_WITH_AVATAR_d4ab2424_Windows.zip'
    if(Test-Path $near){$DonorZip=$near}else{throw 'Original resource ZIP not found. Pass -DonorZip with the d4ab2424 Windows ZIP path.'}
}
$donorHash=(Get-FileHash -LiteralPath $DonorZip -Algorithm SHA256).Hash.ToLowerInvariant()
if($donorHash -ne '8aa26b4fe80a73e35b77dd5252b4a9620e3c89097d53b18773439a6f2390e703'){
    throw "Wrong original resource ZIP SHA256: $donorHash. No resources copied."
}
if([string]::IsNullOrWhiteSpace($Destination)){$Destination=Join-Path $PSScriptRoot ('DWS_PLAYTEST_R1_'+$meta.product_head.Substring(0,8))}
if(Test-Path -LiteralPath $Destination){throw "Destination already exists: $Destination. Existing worlds are not overwritten; choose a new -Destination."}
New-Item -ItemType Directory $Destination|Out-Null
$stage=Join-Path $Destination 'DWS_PLAYTEST_R1'
[System.IO.Compression.ZipFile]::ExtractToDirectory($payload,$Destination)
if(-not(Test-Path (Join-Path $stage 'project/project.godot'))){throw 'INVALID_PRODUCT_PAYLOAD'}
# Reuse only verified engine/model resources, NEVER the old project's code/saves.
$archive=[System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $DonorZip))
try{
    foreach($entry in $archive.Entries){
        $name=$entry.FullName.Replace('\','/')
        $prefix='CHAR1_REALISTIC_WITH_AVATAR/'
        if(-not $name.StartsWith($prefix)){continue}
        $relative=$name.Substring($prefix.Length)
        if(-not($relative.StartsWith('runtime/') -or $relative.StartsWith('project/assets/external/quaternius/') -or $relative.StartsWith('LICENSES/'))){continue}
        if($relative -match '\.(ttf|otf|woff|woff2)$'){continue}
        $target=[IO.Path]::GetFullPath((Join-Path $stage $relative))
        $safeRoot=[IO.Path]::GetFullPath($stage).TrimEnd('\')+'\'
        if(-not $target.StartsWith($safeRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_RESOURCE_PATH'}
        if($name.EndsWith('/')){New-Item -ItemType Directory -Force $target|Out-Null;continue}
        New-Item -ItemType Directory -Force (Split-Path $target)|Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
    }
}finally{$archive.Dispose()}
$project=Join-Path $stage 'project'
$hashes=Get-Content (Join-Path $stage 'SOURCE_SHA256.json') -Raw|ConvertFrom-Json
foreach($prop in $hashes.PSObject.Properties){
    $file=Join-Path $project $prop.Name
    if(-not(Test-Path -LiteralPath $file)){throw "SOURCE_MISSING:$($prop.Name)"}
    if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $prop.Value){throw "SOURCE_HASH_MISMATCH:$($prop.Name)"}
}
$console=Join-Path $stage 'runtime/godot.windows.editor.double.x86_64.console.exe'
$engineHash=(Get-FileHash $console -Algorithm SHA256).Hash.ToLowerInvariant()
if($engineHash -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5'){throw 'ENGINE_SHA_MISMATCH'}
$evidence=Join-Path $stage 'evidence'
New-Item -ItemType Directory -Force $evidence|Out-Null
. (Join-Path $stage 'tools/CHAR1-Common.ps1')
$oldDisabled=$env:BREAKPOINT_RUNTIME_DISABLED
$env:BREAKPOINT_RUNTIME_DISABLED='1'
try{
    $preflight=Invoke-CHAR1Command $console $project @('--headless','--script','res://scripts/characters/importing/quaternius_asset_preflight.gd') 'rc1-asset-preflight' 180
    if(-not $preflight.Contains('asset preflight: PASS')){throw 'ASSET_PREFLIGHT_PASS_MISSING'}
    [void](Invoke-CHAR1Command $console $project @('--headless','--editor','--import') 'rc1-cold-import' 1200)
    $tests=@(
        @{script='tests/characters/test_char1_embedded_quaternius_assets.gd';marker='CHAR1 EMBEDDED REAL AVATAR: PASS'},
        @{script='tests/characters/test_char2_network_avatar_client_presentation.gd';marker='CHAR2 NETWORK AVATAR CLIENT: PASS'},
        @{script='tests/characters/test_char2_product_camera_toggle.gd';marker='CHAR2 PRODUCT CAMERA: PASS'},
        @{script='tests/runtime/test_playtest_launch_profile.gd';marker='PLAYTEST LAUNCH PROFILE: PASS'},
        @{script='tests/runtime/test_user1_seam_recovery_tick_resync.gd';marker='USER1 SEAM RECOVERY TICK RESYNC: PASS'},
        @{script='tests/runtime/test_user1_seam_recovery_port_rebind.gd';marker='USER1 POST-RESTORE SEAM PORT REBIND: PASS'},
        @{script='tests/runtime/test_net_smooth1_remote_owner_reconnect.gd';marker='NET_SMOOTH1_REMOTE_RECONNECT: PASS'}
    )
    foreach($test in $tests){
        $name=[IO.Path]::GetFileNameWithoutExtension($test.script)
        [void](Invoke-CHAR1Command $console $project @('--headless','--script',('res://'+$test.script)) $name 180)
        $receipt=Get-Content -LiteralPath (Join-Path $evidence ($name+'.stdout.log')) -Raw
        if(-not $receipt.Contains($test.marker)){throw "NATIVE_PASS_RECEIPT_MISSING:$name"}
    }
}finally{
    [Environment]::SetEnvironmentVariable('BREAKPOINT_RUNTIME_DISABLED',$oldDisabled,'Process')
}
$embedded=[ordered]@{
    package='DWS Playtest R1';product_head=$meta.product_head;product_tree=$meta.product_tree;
    launch_profile='PLAYTEST_R1_SAFE60';resource_donor_sha256=$donorHash;
    godot_console_sha256=$engineHash;godot_gui_sha256=(Get-FileHash (Join-Path $stage 'runtime/godot.windows.editor.double.x86_64.exe') -Algorithm SHA256).Hash.ToLowerInvariant();
    native_windows='PASS';real_avatar_gate='PASS';gui_human_acceptance='PENDING';
    installed=(Get-Date).ToString('o')
}
$embedded|ConvertTo-Json -Depth 5|Set-Content (Join-Path $stage 'EMBEDDED_BUILD_INFO.json') -Encoding UTF8
if(-not $NoZip){
    $cache=Join-Path $project '.godot'
    if(Test-Path $cache){Remove-Item -LiteralPath $cache -Recurse -Force} # Only this newly created package cache.
    $zip=Join-Path $Destination ('DWS_PLAYTEST_R1_'+$meta.product_head.Substring(0,12)+'_Windows.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip,[IO.Compression.CompressionLevel]::Optimal,$true)
    (Get-FileHash $zip -Algorithm SHA256)|Format-List
    Write-Host "Full Windows ZIP: $zip" -ForegroundColor Green
}
Write-Host "Launch: $(Join-Path $stage 'START.cmd')" -ForegroundColor Green
Write-Host 'Native gates passed; visible two-player GUI must still be tested by the user.'
if($Launch){Start-Process -FilePath (Join-Path $stage 'START.cmd') -WorkingDirectory $stage}
