param(
    [string]$Worktree = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [string]$ExpectedHead = "",
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Worktree)) {
    $Worktree = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$Worktree = (Resolve-Path -LiteralPath $Worktree).Path
if (-not (Test-Path -LiteralPath $GodotConsole)) {
    throw ("CHAR1_GODOT_NOT_FOUND:{0}" -f $GodotConsole)
}
$head = (& git -C $Worktree rev-parse HEAD | Out-String).Trim()
$tree = (& git -C $Worktree rev-parse 'HEAD^{tree}' | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $head -ne $ExpectedHead) {
    throw ("CHAR1_HEAD_MISMATCH:{0}:{1}" -f $head,$ExpectedHead)
}
$version = (& $GodotConsole --version | Out-String).Trim()
$sha = (Get-FileHash -LiteralPath $GodotConsole -Algorithm SHA256).Hash.ToLowerInvariant()
if ($version -ne "4.7.1.stable.double.custom_build.a13da4feb") {
    throw ("CHAR1_GODOT_VERSION_MISMATCH:{0}" -f $version)
}
if ($sha -ne "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5") {
    throw ("CHAR1_GODOT_SHA_MISMATCH:{0}" -f $sha)
}
$evidenceRoot = Join-Path $Worktree "artifacts\char1-graphical"
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$stdout = Join-Path $evidenceRoot "char1-graphical.stdout.log"
$stderr = Join-Path $evidenceRoot "char1-graphical.stderr.log"
$quotedWorktree = '"{0}"' -f $Worktree
$arguments = @("--rendering-driver", "opengl3", "--path", $quotedWorktree, "--script", "res://tests/characters/test_char1_graphical_render.gd")
$process = Start-Process -FilePath $GodotConsole -ArgumentList $arguments -WorkingDirectory $Worktree -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill()
    throw "CHAR1_GRAPHICAL_TIMEOUT"
}
if ($process.ExitCode -ne 0) {
    Get-Content $stdout -Tail 100
    Get-Content $stderr -Tail 100
    throw ("CHAR1_GRAPHICAL_FAILED:{0}" -f $process.ExitCode)
}
$stdoutContent = Get-Content $stdout -Raw
if ($stdoutContent -notmatch "CHAR1 GRAPHICAL: PASS") {
    throw "CHAR1_GRAPHICAL_PASS_MARKER_MISSING"
}
foreach ($file in @("quaternius-or-fallback.png", "procedural.png")) {
    $image = Join-Path $evidenceRoot $file
    if (-not (Test-Path -LiteralPath $image) -or (Get-Item -LiteralPath $image).Length -lt 2048) {
        throw ("CHAR1_RENDER_IMAGE_MISSING_OR_EMPTY:{0}" -f $file)
    }
}
$report = [ordered]@{
    product_head = $head
    product_tree = $tree
    godot_version = $version
    godot_sha256 = $sha
    output = "PASS"
    first_renderer = "quaternius-or-fallback"
    second_renderer = "procedural"
    screenshot_paths = @("quaternius-or-fallback.png", "procedural.png")
}
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidenceRoot "char1-graphical-verdict.json") -Encoding UTF8
Write-Host "CHAR1 GRAPHICAL: PASS ($head)"
