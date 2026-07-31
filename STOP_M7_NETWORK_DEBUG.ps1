param([string]$SessionId = "manual")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunRoot = Join-Path $Root "artifacts/runtime/m7-network-debug/$SessionId"
if (-not (Test-Path $RunRoot)) {
    Write-Host "No M7 debug session found: $SessionId"
    exit 0
}
$Stopped = 0
Get-ChildItem -Path $RunRoot -Filter process.json -Recurse -File | ForEach-Object {
    try {
        $Descriptor = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $ProcessId = [int]$Descriptor.pid
        $Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($null -ne $Process) {
            Stop-Process -Id $ProcessId -Force
            $Stopped++
            Write-Host "Stopped $($Descriptor.role), PID $ProcessId"
        }
    }
    catch {
        Write-Warning "Could not process $($_.FullName): $($_.Exception.Message)"
    }
}
Write-Host "Stopped processes: $Stopped" -ForegroundColor Green
Write-Host "Logs remain in: $RunRoot"
