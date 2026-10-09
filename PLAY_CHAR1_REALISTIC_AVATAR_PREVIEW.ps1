param(
    [string]$Worktree = "",
    [string]$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
)

# Opens the CHAR1 realistic avatar preview window (real Quaternius character,
# third-person start, C/V first-person toggle). The window stays open for
# manual inspection; this script prints and stores the viewer PID.
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Worktree)) {
    $Worktree = (Resolve-Path (Join-Path $PSScriptRoot ".")).Path
}
$Worktree = (Resolve-Path -LiteralPath $Worktree).Path
if (-not (Test-Path -LiteralPath $GodotConsole)) {
    throw ("CHAR1_GODOT_NOT_FOUND:{0}" -f $GodotConsole)
}
$evidenceRoot = Join-Path $Worktree "artifacts\char1-viewmode"
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$stdout = Join-Path $evidenceRoot "viewer.stdout.log"
$stderr = Join-Path $evidenceRoot "viewer.stderr.log"
$arguments = @("--rendering-driver", "opengl3", "--path", ('"{0}"' -f $Worktree), "res://scenes/labs/character/char1_realistic_avatar_viewer.tscn")
$process = Start-Process -FilePath $GodotConsole -ArgumentList $arguments -WorkingDirectory $Worktree -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$process.Id | Set-Content (Join-Path $evidenceRoot "viewer.pid") -Encoding ASCII
Write-Host ("CHAR1 REALISTIC AVATAR PREVIEW: window opened (PID {0})" -f $process.Id)
Write-Host "Controls: [1] Quaternius real  [2] procedural standard  [3] high visibility"
Write-Host "          [C]/[V] first/third person  [I]dle [W]alk [R]un  mouse orbit / wheel zoom"
Write-Host "The window stays open for manual inspection."
