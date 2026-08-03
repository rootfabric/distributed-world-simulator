param(
    [string]$GodotPath = "",
    [ValidateRange(1, 1000)]
    [int]$Iterations = 100,
    [ValidateRange(1, 32)]
    [int]$BatchSize = 8,
    [ValidateRange(30, 3600)]
    [int]$BatchTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @()
if ($GodotPath) { $Candidates += $GodotPath }
if ($env:GODOT_BIN) { $Candidates += $env:GODOT_BIN }
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
    throw "Godot executable not found. Set GODOT_BIN or pass -GodotPath with Godot 4.7.1 double."
}

function ConvertTo-NativeProcessArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $Backslash = [char]0x5C
    $Quote = [char]0x22
    $Builder = [System.Text.StringBuilder]::new()
    [void]$Builder.Append($Quote)
    $BackslashCount = 0

    foreach ($Character in $Value.ToCharArray()) {
        if ($Character -eq $Backslash) {
            $BackslashCount += 1
            continue
        }
        if ($Character -eq $Quote) {
            if ($BackslashCount -gt 0) {
                [void]$Builder.Append(([string]$Backslash * ($BackslashCount * 2)))
            }
            [void]$Builder.Append($Backslash)
            [void]$Builder.Append($Quote)
            $BackslashCount = 0
            continue
        }
        if ($BackslashCount -gt 0) {
            [void]$Builder.Append(([string]$Backslash * $BackslashCount))
            $BackslashCount = 0
        }
        [void]$Builder.Append($Character)
    }

    if ($BackslashCount -gt 0) {
        [void]$Builder.Append(([string]$Backslash * ($BackslashCount * 2)))
    }
    [void]$Builder.Append($Quote)
    return $Builder.ToString()
}

function Add-ProcessArgument {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($StartInfo.PSObject.Properties.Name -contains "ArgumentList") {
        $StartInfo.ArgumentList.Add($Value)
        return
    }

    $Encoded = ConvertTo-NativeProcessArgument -Value $Value
    if ($StartInfo.Arguments.Length -gt 0) {
        $StartInfo.Arguments += " "
    }
    $StartInfo.Arguments += $Encoded
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $Process.Refresh()
    if ($Process.HasExited) { return }
    try {
        if ($Process.PSObject.Methods.Name -contains "Kill" -and $PSVersionTable.PSEdition -eq "Core") {
            $Process.Kill($true)
        }
        else {
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    }
    catch {
        $Process.Refresh()
        if (-not $Process.HasExited) { $Process.Kill() }
    }
}

function Invoke-RaceBatch {
    param(
        [Parameter(Mandatory = $true)][int]$BatchIndex,
        [Parameter(Mandatory = $true)][int]$FirstRound,
        [Parameter(Mandatory = $true)][int]$Rounds
    )

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $GodotExecutable
    $StartInfo.WorkingDirectory = $RootDir
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    foreach ($Argument in @(
        "--headless",
        "--path", $RootDir,
        "--script", "res://tests/matter/handoff/test_mw9_durable_handoff_processes.gd",
        "--",
        "--claim-race-only=true",
        "--claim-race-rounds=$Rounds"
    )) {
        Add-ProcessArgument -StartInfo $StartInfo -Value $Argument
    }

    Write-Host "MW9 race stress runner: batch $BatchIndex, rounds $FirstRound-$($FirstRound + $Rounds - 1)/$Iterations"
    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) { throw "Failed to start Godot process." }
        $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $StderrTask = $Process.StandardError.ReadToEndAsync()
        $Completed = $Process.WaitForExit($BatchTimeoutSeconds * 1000)
        if (-not $Completed) {
            Stop-ProcessTree -Process $Process
            if (-not $Process.WaitForExit(10000)) {
                throw "Batch did not terminate after timeout."
            }
        }
        else {
            $Process.WaitForExit()
        }
        $Process.Refresh()
        $Stdout = $StdoutTask.GetAwaiter().GetResult()
        $Stderr = $StderrTask.GetAwaiter().GetResult()
        if ($Stdout) { [Console]::Out.Write($Stdout) }
        if ($Stderr) { [Console]::Error.Write($Stderr) }
        if (-not $Completed) { throw "Batch exceeded ${BatchTimeoutSeconds}s." }
        if (-not $Process.HasExited) { throw "Process exit state is unavailable after WaitForExit and Refresh." }
        if ($Process.ExitCode -ne 0) { throw "Godot exited with code $($Process.ExitCode)." }
        $Combined = $Stdout + "`n" + $Stderr
        if ($Combined -match 'SCRIPT ERROR:|Parse Error:') {
            throw "Godot reported a script or parse error."
        }
        if (-not $Combined.Contains("MW9 claim race stress: PASS (") -or
            -not $Combined.Contains(", $Rounds rounds)")) {
            throw "Required PASS marker for $Rounds rounds was not printed."
        }
    }
    finally {
        $Process.Dispose()
    }
}

$CompletedRounds = 0
$BatchIndex = 0
while ($CompletedRounds -lt $Iterations) {
    $Rounds = [Math]::Min($BatchSize, $Iterations - $CompletedRounds)
    $BatchIndex += 1
    Invoke-RaceBatch `
        -BatchIndex $BatchIndex `
        -FirstRound ($CompletedRounds + 1) `
        -Rounds $Rounds
    $CompletedRounds += $Rounds
}

Write-Host "MW9 race stress runner: PASS ($Iterations rounds in $BatchIndex batches)"
