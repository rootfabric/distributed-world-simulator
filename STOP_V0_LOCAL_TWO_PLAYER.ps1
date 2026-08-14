param([switch]$Force)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ActiveSessionPath = Join-Path $Root "artifacts/runtime/v0-local-two-player-active.json"

if (-not (Test-Path $ActiveSessionPath)) {
    Write-Host "No active V0 local two-player session was found."
    exit 0
}

$Session = Get-Content $ActiveSessionPath -Raw | ConvertFrom-Json
$Pids = @($Session.client_pids) + @($Session.server_pid)
foreach ($ProcessId in $Pids) {
    $Process = Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue
    if ($null -eq $Process) { continue }
    try {
        if ($Force) { Stop-Process -Id $Process.Id -Force }
        else { Stop-Process -Id $Process.Id }
    }
    catch {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

Start-Sleep -Milliseconds 500
Remove-Item $ActiveSessionPath -Force
Write-Host "V0 local two-player session stopped. Logs remain in $($Session.run_root)" -ForegroundColor Green
