# Run with Windows PowerShell 5.1, not pwsh 7.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) {
    throw ('CHAR1_NEEDS_WINDOWS_POWERSHELL_5_1: {0}' -f $PSVersionTable.PSVersion)
}
$common = Join-Path $PSScriptRoot '..\tools\CHAR1-Common.ps1'
$contents = Get-Content -LiteralPath $common -Raw
$handle = $contents.IndexOf('$null = $process.Handle')
$wait = $contents.IndexOf('WaitForExit(')
if ($handle -lt 0 -or $wait -lt 0 -or $handle -ge $wait) {
    throw 'CHAR1_PS51_PROCESS_HANDLE_GUARD_NOT_PRESENT'
}
$checks = 0
for ($i = 0; $i -lt 32; $i++) {
    # Rapid zero-exit process approximates an already-finished Godot cold import.
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c exit 0' -WindowStyle Hidden -PassThru
    $null = $process.Handle
    if (-not $process.WaitForExit(10000)) {
        $process.Kill()
        throw ('CHAR1_PS51_PROCESS_TIMEOUT: {0}' -f $i)
    }
    if ($null -eq $process.ExitCode -or $process.ExitCode -ne 0) {
        throw ('CHAR1_PS51_FAST_EXIT_INVALID: {0}: {1}' -f $i,$process.ExitCode)
    }
    $process.Dispose()
    $checks += 1
}
$bad = Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c exit 17' -WindowStyle Hidden -PassThru
$null = $bad.Handle
if (-not $bad.WaitForExit(10000)) {
    $bad.Kill()
    throw 'CHAR1_PS51_NONZERO_PROCESS_TIMEOUT'
}
if ($null -eq $bad.ExitCode -or $bad.ExitCode -ne 17) {
    throw ('CHAR1_PS51_NONZERO_EXIT_WRONG: {0}' -f $bad.ExitCode)
}
$bad.Dispose()
$checks += 1
Write-Host ('CHAR1 PS5.1 FAST EXIT: PASS ({0}/0)' -f $checks) -ForegroundColor Green
