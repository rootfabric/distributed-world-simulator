$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $ProjectRoot
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $IncludeExtensions = @(
        ".gd",
        ".uid",
        ".tscn",
        ".tres",
        ".scn",
        ".escn",
        ".gdshader",
        ".gd_shader",
        ".gdshaderinc",
        ".cfg",
        ".json",
        ".import",
        ".png",
        ".svg",
        ".webp",
        ".jpg",
        ".jpeg",
        ".ogg",
        ".wav",
        ".mp3",
        ".tres",
        ".ttf",
        ".otf",
        ".woff",
        ".woff2",
        ".py",
        ".md",
        ".txt",
        ".ps1",
        ".sh",
        ".bat",
        ".gitattributes",
        ".gitignore"
    )

    $ProjectRootFiles = @(
        "project.godot",
        "main.tscn",
        "AGENTS.md",
        "README_RU.md",
        "NETWORK_ROADMAP_RU.md",
        "PROJECT_MANIFEST.txt"
    )

    $ExcludeDirectoryNames = @(
        ".git",
        ".godot",
        ".import",
        ".vscode",
        ".idea",
        "artifacts",
        "node_modules"
    )

    $ExcludeDirectoryPatterns = @(
        "^\.c\d.*-stage-",
        "^\.tmp",
        "^\.cache"
    )

    $ExcludeFilePatterns = @(
        "\.zip$",
        "\.tmp$",
        "\.bak$",
        "\.swp$",
        "\.swo$",
        "^Thumbs\.db$",
        "^desktop\.ini$",
        "^\.DS_Store$",
        "^mono_crash\..*\.json$"
    )

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $DefaultOutputName = "lunar-world-double-godot-$Timestamp.zip"
    $OutputPath = Join-Path $ProjectRoot $DefaultOutputName
    $TopLevelName = Split-Path -Leaf $ProjectRoot

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    $IncludeRegex = "\.(" + (($IncludeExtensions | ForEach-Object { $_.TrimStart('.') }) -join "|") + ")$"

    function Test-ShouldIncludeFile {
        param([System.IO.FileInfo]$File)
        $relative = $File.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
        foreach ($pattern in $ExcludeFilePatterns) {
            if ($relative -match $pattern) { return $false }
        }
        if ($relative -notmatch $IncludeRegex) { return $false }
        return $true
    }

    function Test-ShouldIncludeDirectory {
        param([System.IO.DirectoryInfo]$Directory)
        $name = $Directory.Name
        if ($ExcludeDirectoryNames -contains $name) { return $false }
        foreach ($pattern in $ExcludeDirectoryPatterns) {
            if ($name -match $pattern) { return $false }
        }
        return $true
    }

    function Get-IncludeRoots {
        $roots = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
        $visited = New-Object 'System.Collections.Generic.HashSet[string]'

        $projectRootInfo = Get-Item -LiteralPath $ProjectRoot
        foreach ($entry in (Get-ChildItem -LiteralPath $ProjectRoot -Force)) {
            if (-not $entry.PSIsContainer) { continue }
            $relative = $entry.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
            if ($visited.Contains($relative)) { continue }
            if (-not (Test-ShouldIncludeDirectory $entry)) {
                Write-Host "Skipping directory: $relative"
                $visited.Add($relative) | Out-Null
                continue
            }
            $roots.Add($entry)
            $visited.Add($relative) | Out-Null
        }
        return $roots
    }

    Write-Host "Building Godot package archive..."
    Write-Host "Project root : $ProjectRoot"
    Write-Host "Output path  : $OutputPath"

    $includedFiles = New-Object System.Collections.Generic.List[string]
    $skippedFiles = New-Object System.Collections.Generic.List[string]

    $includedProjectRootFiles = @()
    foreach ($fileName in $ProjectRootFiles) {
        $candidate = Join-Path $ProjectRoot $fileName
        if (Test-Path -LiteralPath $candidate) {
            $info = Get-Item -LiteralPath $candidate
            if (-not $info.PSIsContainer) {
                $includedProjectRootFiles += $info
            }
        }
    }

    $zip = [System.IO.Compression.ZipFile]::Open($OutputPath, [System.IO.Compression.ZipArchiveMode]::Create)

    try {
        foreach ($file in $includedProjectRootFiles) {
            $entryName = [System.IO.Path]::Combine($TopLevelName, $file.Name).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
            $includedFiles.Add($file.Name) | Out-Null
        }

        foreach ($root in (Get-IncludeRoots)) {
            $stack = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
            $stack.Push($root)
            while ($stack.Count -gt 0) {
                $current = $stack.Pop()
                foreach ($child in (Get-ChildItem -LiteralPath $current.FullName -Force)) {
                    if ($child.PSIsContainer) {
                        if (Test-ShouldIncludeDirectory $child) {
                            $stack.Push($child)
                        } else {
                            $relativeDir = $child.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
                            Write-Host "Skipping directory: $relativeDir"
                        }
                        continue
                    }
                    $relative = $child.FullName.Substring($ProjectRoot.Length).TrimStart('\', '/')
                    if (Test-ShouldIncludeFile $child) {
                        $entryName = [System.IO.Path]::Combine($TopLevelName, $relative).Replace('\', '/')
                        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $child.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
                        $includedFiles.Add($relative) | Out-Null
                    } else {
                        $skippedFiles.Add($relative) | Out-Null
                    }
                }
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    $size = (Get-Item -LiteralPath $OutputPath).Length
    $sizeMb = "{0:N2}" -f ($size / 1MB)

    Write-Host ""
    Write-Host "Package built successfully."
    Write-Host "Archive         : $OutputPath"
    Write-Host "Size            : $sizeMb MB ($size bytes)"
    Write-Host "Files included  : $($includedFiles.Count)"
    Write-Host "Files skipped   : $($skippedFiles.Count)"
    Write-Host ""
    Write-Host "Distribution checklist:"
    Write-Host "  1. Share the archive with the recipient."
    Write-Host "  2. Unzip into a clean directory."
    Write-Host "  3. Open project.godot in Godot 4 to reimport assets."
    Write-Host "  4. See README_RU.md for usage and AGENTS.md for delivery rules."
}
finally {
    Pop-Location
}
