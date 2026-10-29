Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-CHAR1Root {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Assert-CHAR1Snapshot([string] $PackageRoot) {
    $infoFile = Join-Path $PackageRoot 'BUILD_INFO.json'
    if (-not (Test-Path -LiteralPath $infoFile)) { throw 'CHAR1_BUILD_INFO_MISSING' }
    $info = Get-Content -LiteralPath $infoFile -Raw | ConvertFrom-Json
    foreach ($entry in $info.critical_sha256.PSObject.Properties) {
        $file = Join-Path (Join-Path $PackageRoot 'project') ($entry.Name.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $file)) { throw ('CHAR1_MISSING_SOURCE:{0}' -f $entry.Name) }
        $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $entry.Value) { throw ('CHAR1_SOURCE_MISMATCH:{0}' -f $entry.Name) }
    }
    Write-Host ('Source verified: {0} (tree {1})' -f $info.product_head,$info.product_tree) -ForegroundColor Green
    return $info
}

function Resolve-CHAR1Godot([string] $ExplicitConsole) {
    $candidates = @()
    if ($ExplicitConsole) { $candidates += $ExplicitConsole }
    if ($env:GODOT_BIN) { $candidates += $env:GODOT_BIN }
    $candidates += @(
        'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe',
        'C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe'
    )
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $bin = (Resolve-Path -LiteralPath $candidate).Path
        $version = (& $bin --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $version -ne '4.7.1.stable.double.custom_build.a13da4feb') {
            throw ('CHAR1_GODOT_VERSION_MISMATCH:{0}' -f $version)
        }
        $sha = (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -ne '3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5') {
            throw ('CHAR1_GODOT_HASH_MISMATCH:{0}' -f $sha)
        }
        $gui = $bin.Replace('.console.exe', '.exe')
        if (-not (Test-Path -LiteralPath $gui -PathType Leaf)) {
            throw ('CHAR1_GODOT_GUI_NOT_FOUND:{0}' -f $gui)
        }
        Write-Host ('Godot verified: {0}' -f $version) -ForegroundColor Green
        return @{ Console = $bin; GUI = $gui; Version = $version; Sha256 = $sha }
    }
    throw 'CHAR1_CANONICAL_GODOT_NOT_FOUND: use -GodotConsole to select installed 4.7.1 double console.exe'
}

function Get-CHAR1ModelCount([string] $Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return 0 }
    return @(
        Get-ChildItem -LiteralPath $Directory -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @('.glb', '.gltf', '.fbx') }
    ).Count
}

function Test-CHAR1AssetRoot([string] $Root) {
    if (-not $Root) { return $false }
    $base = Get-CHAR1ModelCount (Join-Path $Root 'base_characters')
    $animation = Get-CHAR1ModelCount (Join-Path $Root 'animation_library')
    return ($base -gt 0 -and $animation -gt 0)
}

function Ensure-CHAR1RealAssets([string] $PackageRoot, [string] $RequestedSource) {
    $project = Join-Path $PackageRoot 'project'
    $dest = Join-Path $project 'assets\external\quaternius'
    if (Test-CHAR1AssetRoot $dest) {
        Write-Host 'Quaternius assets already present inside the portable project.' -ForegroundColor Green
        return $dest
    }
    $candidates = @()
    if ($RequestedSource) { $candidates += $RequestedSource }
    if ($env:DWS_QUATERNIUS_ASSET_ROOT) { $candidates += $env:DWS_QUATERNIUS_ASSET_ROOT }
    $candidates += @(
        'C:\distributed-world-simulator\char1-realistic-r1\assets\external\quaternius',
        'C:\distributed-world-simulator\work\char1-realistic-r1\assets\external\quaternius',
        'C:\distributed-world-simulator\assets\external\quaternius',
        'C:\distributed-world-simulator\work\char1-realistic-r1',
        (Join-Path (Split-Path -Parent $PackageRoot) 'char1-realistic-r1\assets\external\quaternius')
    )
    $source = $null
    foreach ($raw in $candidates) {
        if (-not $raw) { continue }
        $candidate = $raw
        if (-not (Test-CHAR1AssetRoot $candidate)) {
            $nested = Join-Path $candidate 'assets\external\quaternius'
            if (Test-CHAR1AssetRoot $nested) { $candidate = $nested }
        }
        if (Test-CHAR1AssetRoot $candidate) {
            $source = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
    if ($source) {
        if (-not (Test-Path -LiteralPath $dest)) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
        Write-Host ('Copying real CC0 Quaternius assets from: {0}' -f $source) -ForegroundColor Cyan
        foreach ($folder in @('base_characters','animation_library')) {
            $target = Join-Path $dest $folder
            if ((Get-CHAR1ModelCount $target) -gt 0) { continue }
            if (Test-Path -LiteralPath $target) {
                throw ('CHAR1_INCOMPLETE_ASSET_FOLDER:{0}; move aside before retry' -f $target)
            }
            Copy-Item -LiteralPath (Join-Path $source $folder) -Destination $target -Recurse -Force
        }
    }
    else {
        $downloads = Join-Path $env:USERPROFILE 'Downloads'
        $baseZip = @()
        $animationZip = @()
        if (Test-Path -LiteralPath $downloads) {
            $archives = @(Get-ChildItem -LiteralPath $downloads -Filter '*.zip' -File)
            $baseZip = @($archives | Where-Object { $_.Name -like 'Universal Base Characters*Standard*.zip' })
            $animationZip = @($archives | Where-Object { $_.Name -like 'Universal Animation Library*Standard*.zip' -and $_.Name -notlike '*Library 2*' })
        }
        if ($baseZip.Count -gt 0 -and $animationZip.Count -gt 0) {
            $installer = Join-Path $project 'INSTALL_CH4_QUATERNIUS_ASSETS.ps1'
            Write-Host 'Installing official Quaternius ZIP archives from Downloads.' -ForegroundColor Cyan
            & $installer -DownloadsPath $downloads
        }
    }
    if (-not (Test-CHAR1AssetRoot $dest)) {
        throw @'
CHAR1_REAL_ASSETS_NOT_FOUND
Place the CC0 Quaternius Base Characters / Animation Library in either:
  C:\distributed-world-simulator\char1-realistic-r1\assets\external\quaternius\
  OR this package's project\assets\external\quaternius\
Or keep the two original Standard ZIPs in Downloads and retry.
The portable package never silently accepts a procedural avatar as real Quaternius.
'@
    }
    $b = Get-CHAR1ModelCount (Join-Path $dest 'base_characters')
    $a = Get-CHAR1ModelCount (Join-Path $dest 'animation_library')
    Write-Host ('Real Quaternius asset source files: characters={0}, animations={1}' -f $b,$a) -ForegroundColor Green
    return $dest
}

function Invoke-CHAR1Command(
    [string] $GodotExe,
    [string] $Project,
    [string[]] $Arguments,
    [string] $LogStem,
    [int] $TimeoutSeconds = 900
) {
    $logs = Join-Path (Split-Path -Parent $Project) 'evidence'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $output = Join-Path $logs ($LogStem + '.stdout.log')
    $errorFile = Join-Path $logs ($LogStem + '.stderr.log')
    $list = @('--path', ('"{0}"' -f $Project)) + $Arguments
    Write-Host ('Running {0}...' -f $LogStem) -ForegroundColor Cyan
    $process = Start-Process -FilePath $GodotExe -ArgumentList $list -WorkingDirectory $Project -RedirectStandardOutput $output -RedirectStandardError $errorFile -PassThru
    # PS5.1 fast-exit race: initialize the native handle before waiting,
    # otherwise Start-Process -PassThru may expose ExitCode = null.
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        throw ('CHAR1_TIMEOUT:{0}' -f $LogStem)
    }
    if ($null -eq $process.ExitCode) {
        throw ('CHAR1_EXITCODE_MISSING:{0}' -f $LogStem)
    }
    if ($process.ExitCode -ne 0) {
        Get-Content -LiteralPath $output -Tail 35
        Get-Content -LiteralPath $errorFile -Tail 35
        throw ('CHAR1_EXECUTION_FAILED:{0}:{1}' -f $LogStem,$process.ExitCode)
    }
    $combined = (Get-Content -LiteralPath $output -Raw) + [Environment]::NewLine + (Get-Content -LiteralPath $errorFile -Raw)
    if ($combined -match 'SCRIPT ERROR:|Parse Error:|Compile Error:') {
        throw ('CHAR1_SCRIPT_ERRORS:{0}' -f $LogStem)
    }
    return $combined
}
