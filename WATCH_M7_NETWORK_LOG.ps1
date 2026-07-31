param(
    [ValidateSet("server","client-a","client-b","client-c","client-d","client-e","client-f","client-g","client-h")]
    [string]$Role = "server",
    [string]$SessionId = "manual",
    [ValidateRange(1, 5000)][int]$Tail = 120
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $Root "artifacts/runtime/m7-network-debug/$SessionId/$Role/godot.log"
while (-not (Test-Path $LogPath)) {
    Write-Host "Waiting for $LogPath ..."
    Start-Sleep -Milliseconds 250
}
Write-Host "Following $LogPath" -ForegroundColor Cyan
Get-Content -Path $LogPath -Tail $Tail -Wait
