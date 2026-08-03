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
        Name = "contracts/runtime"
        Script = "res://tests/matter/handoff/test_mw9_durable_handoff_recovery.gd"
        Marker = "MW9 durable handoff recovery: PASS (203 assertions)"
    },
    [pscustomobject]@{
        Name = "lock-release-retry"
        Script = "res://tests/matter/handoff/test_mw9_lock_release_retry.gd"
        Marker = "MW9 lock release retry: PASS (12 assertions)"
    },
    [pscustomobject]@{
        Name = "multi-process"
        Script = "res://tests/matter/handoff/test_mw9_durable_handoff_processes.gd"
        Marker = "MW9 durable handoff processes: PASS (225 assertions)"
    }
)

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

function Invoke-Mw9Suite {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Suite,
        [Parameter(Mandatory = $true)]
        [int]$SuiteIndex,
        [Parameter(Mandatory = $true)]
        [int]$SuiteCount
    )

    $Process = $null
    $StdoutTask = $null
    $StderrTask = $null
    $TimedOut = $false
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

        Write-Host "MW9 runner: suite $SuiteIndex/$SuiteCount [$($Suite.Name)]"
        Write-Host "MW9 runner: $($Suite.Script)"

        $Process = [System.Diagnostics.Process]::new()
        $Process.StartInfo = $StartInfo
        if (-not $Process.Start()) {
            throw "Failed to start Godot process."
        }

        $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $StderrTask = $Process.StandardError.ReadToEndAsync()
        $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)
        $TimedOut = -not $Completed

        if ($TimedOut) {
            try {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    $Process.Kill()
                }
            }
            catch {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    throw "Suite timed out and the Godot process could not be terminated: $($_.Exception.Message)"
                }
            }
            if (-not $Process.WaitForExit(10000)) {
                throw "Suite timed out and the Godot process did not terminate after Kill()."
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

        $ExitCode = $null
        if ($Process.HasExited) {
            $Process.Refresh()
            $ExitCode = $Process.ExitCode
        }

        $MarkerFound = ($Stdout + "`n" + $Stderr).Contains($Suite.Marker)
        $ExitCodeAvailable = $null -ne $ExitCode
        $Success = $Completed -and $ExitCodeAvailable -and ([int]$ExitCode -eq 0) -and $MarkerFound

        if (-not $Completed) {
            [Console]::Error.WriteLine(
                "MW9 runner: suite $($Suite.Name) exceeded ${TimeoutSeconds}s and was terminated."
            )
        }
        elseif (-not $ExitCodeAvailable) {
            [Console]::Error.WriteLine(
                "MW9 runner: suite $($Suite.Name) harness failure: process exit code is unavailable after WaitForExit and Refresh."
            )
        }
        elseif ([int]$ExitCode -ne 0) {
            [Console]::Error.WriteLine(
                "MW9 runner: suite $($Suite.Name) exited with code $ExitCode."
            )
        }
        elseif (-not $MarkerFound) {
            [Console]::Error.WriteLine(
                "MW9 runner: suite $($Suite.Name) did not print the required marker: $($Suite.Marker)"
            )
        }

        return [pscustomobject]@{
            Name = $Suite.Name
            Script = $Suite.Script
            Success = $Success
            TimedOut = $TimedOut
            ExitCode = $ExitCode
            ExitCodeAvailable = $ExitCodeAvailable
            MarkerFound = $MarkerFound
            Error = ""
        }
    }
    catch {
        $Message = $_.Exception.Message
        [Console]::Error.WriteLine(
            "MW9 runner: suite $($Suite.Name) harness failure: $Message"
        )
        return [pscustomobject]@{
            Name = $Suite.Name
            Script = $Suite.Script
            Success = $false
            TimedOut = $TimedOut
            ExitCode = $null
            ExitCodeAvailable = $false
            MarkerFound = $false
            Error = $Message
        }
    }
    finally {
        if ($Process) {
            $Process.Dispose()
        }
    }
}

$Results = @()
for ($Index = 0; $Index -lt $Suites.Count; $Index += 1) {
    $Results += Invoke-Mw9Suite `
        -Suite $Suites[$Index] `
        -SuiteIndex ($Index + 1) `
        -SuiteCount $Suites.Count
}

$Failures = @($Results | Where-Object { -not $_.Success })
if ($Failures.Count -gt 0) {
    [Console]::Error.WriteLine(
        "MW9 runner: FAIL ($($Failures.Count)/$($Suites.Count) suites failed)."
    )
    foreach ($Failure in $Failures) {
        $ExitDescription = if ($Failure.ExitCodeAvailable) {
            [string]$Failure.ExitCode
        }
        else {
            "unavailable"
        }
        [Console]::Error.WriteLine(
            "MW9 runner: failed suite [$($Failure.Name)] script=$($Failure.Script) exit=$ExitDescription marker=$($Failure.MarkerFound)"
        )
    }
    if (@($Failures | Where-Object { $_.TimedOut }).Count -gt 0) {
        exit 124
    }
    $FirstNonZeroExitCode = @(
        $Failures |
            Where-Object {
                $_.ExitCodeAvailable -and
                $_.ExitCode -gt 0 -and
                $_.ExitCode -le 255
            } |
            Select-Object -ExpandProperty ExitCode -First 1
    )
    if ($FirstNonZeroExitCode.Count -gt 0) {
        exit ([int]$FirstNonZeroExitCode[0])
    }
    exit 1
}

Write-Host "MW9 runner: PASS ($($Suites.Count)/$($Suites.Count) suites)"
