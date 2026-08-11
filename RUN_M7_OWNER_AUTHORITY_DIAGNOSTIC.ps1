param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [int]$DurationSeconds = 45,
    [string]$NetworkProfile = "LOCAL"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path
$DurationSeconds = [Math]::Max($DurationSeconds, 20)
$DurationMs = $DurationSeconds * 1000
$ServerShutdownMs = $DurationMs + 120000
$NetworkProfile = $NetworkProfile.Trim().ToUpperInvariant()

function Get-FreeTcpPort {
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $Listener.Start()
        return ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
    }
    finally { $Listener.Stop() }
}

function Read-JsonSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
    catch { return $null }
}

function Wait-JsonState {
    param(
        [string]$Path,
        [string[]]$States,
        [int]$TimeoutMs,
        [System.Diagnostics.Process]$Process = $null
    )
    $Started = [Environment]::TickCount64
    while (([Environment]::TickCount64 - $Started) -lt $TimeoutMs) {
        $Value = Read-JsonSafe -Path $Path
        if ($null -ne $Value -and $States -contains [string]$Value.state) { return $Value }
        if ($null -ne $Process -and $Process.HasExited) { return $Value }
        Start-Sleep -Milliseconds 100
    }
    return (Read-JsonSafe -Path $Path)
}

function Start-IsolatedGodot {
    param([string[]]$Arguments, [string]$UserRoot)
    $Names = @(
        "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
        "APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED",
        "GODOT_SILENCE_ROOT_WARNING"
    )
    $Saved = @{}
    foreach ($Name in $Names) {
        $Saved[$Name] = [pscustomobject]@{
            Exists = [Environment]::GetEnvironmentVariable($Name, "Process") -ne $null
            Value = [Environment]::GetEnvironmentVariable($Name, "Process")
        }
    }
    foreach ($Path in @($UserRoot, (Join-Path $UserRoot "data"), (Join-Path $UserRoot "config"), (Join-Path $UserRoot "cache"))) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
    try {
        [Environment]::SetEnvironmentVariable("HOME", $UserRoot, "Process")
        [Environment]::SetEnvironmentVariable("XDG_DATA_HOME", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", (Join-Path $UserRoot "config"), "Process")
        [Environment]::SetEnvironmentVariable("XDG_CACHE_HOME", (Join-Path $UserRoot "cache"), "Process")
        [Environment]::SetEnvironmentVariable("APPDATA", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("LOCALAPPDATA", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "1", "Process")
        [Environment]::SetEnvironmentVariable("GODOT_SILENCE_ROOT_WARNING", "1", "Process")
        return Start-Process -FilePath $Godot -ArgumentList $Arguments -PassThru
    }
    finally {
        foreach ($Name in $Names) {
            if ($Saved[$Name].Exists) {
                [Environment]::SetEnvironmentVariable($Name, [string]$Saved[$Name].Value, "Process")
            }
            else { [Environment]::SetEnvironmentVariable($Name, $null, "Process") }
        }
    }
}

function Stop-ProcessSafe {
    param([System.Diagnostics.Process]$Process)
    try {
        if ($null -ne $Process -and -not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Write-OwnerClientSummary {
    param([object]$Result, [string]$Label)
    if ($null -eq $Result) {
        Write-Host "Client ${Label}: no result JSON" -ForegroundColor Yellow
        return
    }
    $Prediction = $Result.world_report.m7_prediction_report
    $Runtime = $Result.runtime_report
    $Remote = $Result.world_report.fix10_fix3_remote_continuity
    Write-Host ("Client {0}: state={1}, corrections={2}, max_error={3:N4}m, owner_states={4}, owner_send_failures={5}, owner_snapshot_reconcile_skips={6}, remote_gap={7}, remote_underruns={8}, remote_holds={9}" -f `
        $Label, [string]$Result.state, [int]$Prediction.corrections, [double]$Prediction.maximum_error_m, `
        [int]$Runtime.owner_state_submissions, [int]$Runtime.owner_state_send_failures, `
        [int]$Runtime.owner_snapshot_reconciliations_skipped, [int]$Remote.max_snapshot_gap_ticks, `
        [int]$Remote.moving_buffer_underruns, [int]$Remote.moving_hold_samples)
    if ($null -ne $Result.failures -and @($Result.failures).Count -gt 0) {
        Write-Host ("Client {0} failures: {1}" -f $Label, (@($Result.failures) -join "; ")) -ForegroundColor Yellow
    }
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = Join-Path $ProjectRoot "artifacts\test-results\m7-owner-authority-diagnostic-$Timestamp"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ServerJson = Join-Path $OutDir "server.json"
$ClientAJson = Join-Path $OutDir "a.json"
$ClientBJson = Join-Path $OutDir "b.json"
$ServerLog = Join-Path $OutDir "server.log"
$ClientALog = Join-Path $OutDir "a.log"
$ClientBLog = Join-Path $OutDir "b.log"
$Port = Get-FreeTcpPort

$ServerProcess = $null
$ClientAProcess = $null
$ClientBProcess = $null

Write-Host "M7 owner-authoritative locomotion visual diagnostic" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"
Write-Host "Output:  $OutDir"
Write-Host "Profile: $NetworkProfile"
Write-Host "Stress:  $DurationSeconds seconds"

try {
    $ServerArgs = @(
        "--headless", "--quiet", "--path", $ProjectRoot,
        "--log-file", $ServerLog,
        "--script", "res://tools/runtime/m7_fix10_owner_authority_server.gd",
        "--",
        "--server-address=127.0.0.1",
        "--server-port=$Port",
        "--node-id=m7-owner-authority-server",
        "--m7-result-file=$ServerJson",
        "--network-profile=$NetworkProfile",
        "--shutdown-after-ms=$ServerShutdownMs"
    )
    $ServerProcess = Start-IsolatedGodot -Arguments $ServerArgs -UserRoot (Join-Path $OutDir "user-server")
    $ServerReady = Wait-JsonState -Path $ServerJson -States @("READY", "FAILED") -TimeoutMs 30000 -Process $ServerProcess
    if ($null -eq $ServerReady -or [string]$ServerReady.state -ne "READY") {
        throw "Owner-authority server did not reach READY; inspect $ServerLog"
    }
    Write-Host "Server READY on 127.0.0.1:$Port" -ForegroundColor Green

    $CommonClientArgs = @(
        "--quiet", "--path", $ProjectRoot,
        "--rendering-method", "gl_compatibility",
        "--audio-driver", "Dummy"
    )
    $ClientAArgs = $CommonClientArgs + @(
        "--log-file", $ClientALog,
        "--script", "res://tools/runtime/m7_fix10_owner_prediction_client.gd",
        "--",
        "--host=127.0.0.1", "--port=$Port", "--client-id=a", "--phase=1",
        "--result-file=$ClientAJson", "--peer-file=$ClientBJson", "--server-file=$ServerJson",
        "--network-profile=$NetworkProfile", "--duration-ms=$DurationMs", "--diagnostic=1"
    )
    $ClientBArgs = $CommonClientArgs + @(
        "--log-file", $ClientBLog,
        "--script", "res://tools/runtime/m7_fix10_owner_prediction_client.gd",
        "--",
        "--host=127.0.0.1", "--port=$Port", "--client-id=b", "--phase=2",
        "--result-file=$ClientBJson", "--peer-file=$ClientAJson", "--server-file=$ServerJson",
        "--network-profile=$NetworkProfile", "--duration-ms=$DurationMs", "--diagnostic=1"
    )
    $ClientAProcess = Start-IsolatedGodot -Arguments $ClientAArgs -UserRoot (Join-Path $OutDir "user-a")
    $ClientBProcess = Start-IsolatedGodot -Arguments $ClientBArgs -UserRoot (Join-Path $OutDir "user-b")

    $TimeoutMs = $DurationMs + 60000
    $A = Wait-JsonState -Path $ClientAJson -States @("COMPLETE", "FAILED") -TimeoutMs $TimeoutMs -Process $ClientAProcess
    $B = Wait-JsonState -Path $ClientBJson -States @("COMPLETE", "FAILED") -TimeoutMs $TimeoutMs -Process $ClientBProcess
    Write-OwnerClientSummary -Result $A -Label "A"
    Write-OwnerClientSummary -Result $B -Label "B"
    if ($null -eq $A -or [string]$A.state -ne "COMPLETE" -or -not [bool]$A.passed) {
        throw "Owner-authority client A failed; inspect $ClientALog and $ClientAJson"
    }
    if ($null -eq $B -or [string]$B.state -ne "COMPLETE" -or -not [bool]$B.passed) {
        throw "Owner-authority client B failed; inspect $ClientBLog and $ClientBJson"
    }
    Write-Host ""
    Write-Host "Owner-authority visual diagnostic completed - NOT FINAL ACCEPTANCE." -ForegroundColor Yellow
    Write-Host "Results: $OutDir"
}
finally {
    Stop-ProcessSafe -Process $ClientAProcess
    Stop-ProcessSafe -Process $ClientBProcess
    Stop-ProcessSafe -Process $ServerProcess
}