param(
    [string]$Worktree = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    [int]$TimeoutSeconds = 120
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
$evidenceRoot = Join-Path $Worktree "artifacts\char1-viewmode"
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$stdout = Join-Path $evidenceRoot "char1-viewmode.stdout.log"
$stderr = Join-Path $evidenceRoot "char1-viewmode.stderr.log"
$arguments = @("--rendering-driver", "opengl3", "--path", ('"{0}"' -f $Worktree), "--script", "res://tests/characters/test_char1_realistic_viewmode.gd")
$process = Start-Process -FilePath $GodotConsole -ArgumentList $arguments -WorkingDirectory $Worktree -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill()
    throw "CHAR1_VIEWMODE_TIMEOUT"
}
if ($process.ExitCode -ne 0) {
    Get-Content $stdout -Tail 100
    Get-Content $stderr -Tail 100
    throw ("CHAR1_VIEWMODE_FAILED:{0}" -f $process.ExitCode)
}
$stdoutContent = Get-Content $stdout -Raw
if ($stdoutContent -notmatch "CHAR1 VIEWMODE: PASS") {
    Get-Content $stdout -Tail 100
    throw "CHAR1_VIEWMODE_PASS_MARKER_MISSING"
}
foreach ($file in @("viewmode-third-person.png", "viewmode-first-person.png")) {
    $image = Join-Path $evidenceRoot $file
    if (-not (Test-Path -LiteralPath $image) -or (Get-Item -LiteralPath $image).Length -lt 2048) {
        throw ("CHAR1_VIEWMODE_IMAGE_MISSING_OR_EMPTY:{0}" -f $file)
    }
}
$report = [ordered]@{
    product_head = $head
    output = "PASS"
    default_character = "character/quaternius/regular"
    default_view_mode = "THIRD_PERSON"
    screenshots = @("viewmode-third-person.png", "viewmode-first-person.png")
}
$report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidenceRoot "char1-viewmode-verdict.json") -Encoding UTF8
Write-Host "CHAR1 VIEWMODE: PASS ($head)"
