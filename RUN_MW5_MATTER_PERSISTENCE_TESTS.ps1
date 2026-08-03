param(
    [string]$GodotPath = "",
    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if ($GodotPath) {
    $Candidates += $GodotPath
}
if ($env:GODOT_BIN) {
    $Candidates += $env:GODOT_BIN
}
$Candidates += @(
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $RootDir "tools\godot\godot.windows.editor.double.x86_64.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.console.exe"),
    (Join-Path $RootDir "godot.windows.editor.double.x86_64.exe"),
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
)

$GodotExecutable = $null
foreach ($Candidate in $Candidates) {
    if ($Candidate -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        $GodotExecutable = (Resolve-Path -LiteralPath $Candidate).Path
        break
    }
}

if (-not $GodotExecutable) {
    throw "Godot executable not found. Set GODOT_BIN or pass -GodotPath with the Godot 4.7.1 double-precision console/editor binary."
}

$Arguments = @(
    "--headless",
    "--path", ('"{0}"' -f $RootDir),
    "--script", "res://tests/matter/persistence/test_mw5_matter_persistence.gd"
)

Write-Host "MW5 runner: starting with ${TimeoutSeconds}s timeout"
$Process = Start-Process `
    -FilePath $GodotExecutable `
    -ArgumentList $Arguments `
    -NoNewWindow `
    -PassThru

$Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $Process.HasExited) {
    if ([DateTime]::UtcNow -ge $Deadline) {
        try {
            $Process.Kill()
            $Process.WaitForExit()
        }
        catch {
            Write-Warning "Failed to terminate timed-out Godot process: $($_.Exception.Message)"
        }
        [Console]::Error.WriteLine("MW5 focused test exceeded ${TimeoutSeconds}s and was terminated. Last printed stage identifies the hot path.")
        exit 124
    }
    Start-Sleep -Milliseconds 100
    $Process.Refresh()
}

if ($Process.ExitCode -ne 0) {
    exit $Process.ExitCode
}
