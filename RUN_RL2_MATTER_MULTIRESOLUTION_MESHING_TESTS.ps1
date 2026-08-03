param(
    [string]$GodotPath = "",
    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 300
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

$Suites = @(
    [pscustomobject]@{
        Name = "contracts/synthetic"
        Script = "res://tests/representation/test_rl2_matter_multiresolution_meshing.gd"
        Marker = "RL2 Matter multiresolution meshing: PASS (153 assertions)"
    },
    [pscustomobject]@{
        Name = "real-asteroid"
        Script = "res://tests/representation/test_rl2_real_asteroid_multiresolution.gd"
        Marker = "RL2 real asteroid multiresolution: PASS (44 assertions)"
    }
)

function ConvertTo-NativeProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
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
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory = $true)][string]$Value
    )
    if ($StartInfo.PSObject.Properties.Name -contains "ArgumentList") {
        $StartInfo.ArgumentList.Add($Value)
        return
    }
    $Encoded = ConvertTo-NativeProcessArgument -Value $Value
    if ($StartInfo.Arguments.Length -gt 0) { $StartInfo.Arguments += " " }
    $StartInfo.Arguments += $Encoded
}

function Start-Rl2Suite {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Suite,
        [Parameter(Mandatory = $true)][int]$SuiteIndex,
        [Parameter(Mandatory = $true)][int]$SuiteCount
    )
    $Process = $null
    try {
        $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = $GodotExecutable
        $StartInfo.WorkingDirectory = $RootDir
        $StartInfo.UseShellExecute = $false
        $StartInfo.CreateNoWindow = $true
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true
        Add-ProcessArgument -StartInfo $StartInfo -Value "--headless"
        Add-ProcessArgument -StartInfo $StartInfo -Value "--path"
        Add-ProcessArgument -StartInfo $StartInfo -Value $RootDir
        Add-ProcessArgument -StartInfo $StartInfo -Value "--script"
        Add-ProcessArgument -StartInfo $StartInfo -Value $Suite.Script

        Write-Host "RL2 runner: starting suite $SuiteIndex/$SuiteCount [$($Suite.Name)]"
        $Process = [System.Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        if (-not $Process.Start()) { throw "Failed to start Godot process." }
        return [pscustomobject]@{
            Suite = $Suite
            Process = $Process
            StdoutTask = $Process.StandardOutput.ReadToEndAsync()
            StderrTask = $Process.StandardError.ReadToEndAsync()
            StartedAt = [DateTime]::UtcNow
            StartError = ""
        }
    }
    catch {
        if ($Process) { $Process.Dispose() }
        return [pscustomobject]@{
            Suite = $Suite
            Process = $null
            StdoutTask = $null
            StderrTask = $null
            StartedAt = [DateTime]::UtcNow
            StartError = $_.Exception.Message
        }
    }
}

function Complete-Rl2Suite {
    param([Parameter(Mandatory = $true)][pscustomobject]$Context)
    $Suite = $Context.Suite
    $Process = $Context.Process
    if ($null -eq $Process) {
        [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) harness failure: $($Context.StartError)")
        return [pscustomobject]@{ Name = $Suite.Name; Success = $false; TimedOut = $false; ExitCode = $null; ExitCodeAvailable = $false; MarkerFound = $false }
    }

    $TimedOut = $false
    try {
        $ElapsedMs = [int]([DateTime]::UtcNow - $Context.StartedAt).TotalMilliseconds
        $RemainingMs = [Math]::Max(0, ($TimeoutSeconds * 1000) - $ElapsedMs)
        $Completed = $Process.WaitForExit($RemainingMs)
        $TimedOut = -not $Completed
        if ($TimedOut) {
            $Process.Refresh()
            if (-not $Process.HasExited) { $Process.Kill() }
            if (-not $Process.WaitForExit(10000)) {
                throw "Timed-out Godot process did not terminate after Kill()."
            }
        }
        else {
            $Process.WaitForExit()
        }
        $Process.Refresh()
        $Stdout = $Context.StdoutTask.GetAwaiter().GetResult()
        $Stderr = $Context.StderrTask.GetAwaiter().GetResult()
        if ($Stdout) { [Console]::Out.Write($Stdout) }
        if ($Stderr) { [Console]::Error.Write($Stderr) }

        $ExitCode = $null
        if ($Process.HasExited) {
            $Process.Refresh()
            $ExitCode = $Process.ExitCode
        }
        $ExitCodeAvailable = $null -ne $ExitCode
        $CombinedOutput = $Stdout + "`n" + $Stderr
        $MarkerFound = $CombinedOutput.Contains($Suite.Marker)
        $ScriptErrorFound = $CombinedOutput -match '(?m)^(SCRIPT ERROR:|.*Parse Error:)'
        $Success = (-not $TimedOut) -and $ExitCodeAvailable -and ([int]$ExitCode -eq 0) -and $MarkerFound -and (-not $ScriptErrorFound)
        if ($TimedOut) {
            [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) exceeded ${TimeoutSeconds}s and was terminated.")
        }
        elseif (-not $ExitCodeAvailable) {
            [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) harness failure: process exit code is unavailable after WaitForExit and Refresh.")
        }
        elseif ($ScriptErrorFound) {
            [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) printed a Godot script error.")
        }
        elseif ([int]$ExitCode -ne 0) {
            [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) exited with code $ExitCode.")
        }
        elseif (-not $MarkerFound) {
            [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) did not print required marker: $($Suite.Marker)")
        }
        else {
            Write-Host "RL2 runner: suite [$($Suite.Name)] PASS"
        }
        return [pscustomobject]@{ Name = $Suite.Name; Success = $Success; TimedOut = $TimedOut; ExitCode = $ExitCode; ExitCodeAvailable = $ExitCodeAvailable; MarkerFound = $MarkerFound; ScriptErrorFound = $ScriptErrorFound }
    }
    catch {
        [Console]::Error.WriteLine("RL2 runner: suite $($Suite.Name) harness failure: $($_.Exception.Message)")
        return [pscustomobject]@{ Name = $Suite.Name; Success = $false; TimedOut = $TimedOut; ExitCode = $null; ExitCodeAvailable = $false; MarkerFound = $false }
    }
    finally {
        $Process.Dispose()
    }
}

$Contexts = @()
for ($Index = 0; $Index -lt $Suites.Count; $Index += 1) {
    $Contexts += Start-Rl2Suite -Suite $Suites[$Index] -SuiteIndex ($Index + 1) -SuiteCount $Suites.Count
}
$Results = @()
foreach ($Context in $Contexts) {
    $Results += Complete-Rl2Suite -Context $Context
}

$Failures = @($Results | Where-Object { -not $_.Success })
if ($Failures.Count -gt 0) {
    [Console]::Error.WriteLine("RL2 runner: FAIL ($($Failures.Count)/$($Suites.Count) suites failed).")
    if (@($Failures | Where-Object { $_.TimedOut }).Count -gt 0) { exit 124 }
    $FirstNonZeroExitCode = @(
        $Failures |
            Where-Object { $_.ExitCodeAvailable -and $_.ExitCode -gt 0 -and $_.ExitCode -le 255 } |
            Select-Object -ExpandProperty ExitCode -First 1
    )
    if ($FirstNonZeroExitCode.Count -gt 0) { exit ([int]$FirstNonZeroExitCode[0]) }
    exit 1
}

Write-Host "RL2 runner: PASS ($($Suites.Count)/$($Suites.Count) suites)"
