param(
    [Parameter(Mandatory = $true)]
    [int]$ProcessId,

    [int]$Port = 24580,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ServerLog = "",

    [int]$IntervalMs = 500
)

$ErrorActionPreference = "Stop"

if ($IntervalMs -lt 100) {
    throw "INTERVAL_TOO_SMALL"
}

$parent = Split-Path -Parent $OutputPath
if ($parent) {
    New-Item -ItemType Directory -Force $parent | Out-Null
}

function Get-LastStallMarker {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return ""
    }

    $match = Get-Content $Path -Tail 400 -ErrorAction SilentlyContinue |
        Where-Object { $_ -like "*[live2_stall_watchdog]*" } |
        Select-Object -Last 1

    return [string]$match
}

$previousCpu = $null
$previousAt = $null

while ($true) {
    $now = Get-Date
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue

    if ($null -eq $process) {
        [ordered]@{
            at = $now.ToString("o")
            process_id = $ProcessId
            alive = $false
            udp_bound = $false
            last_stall_marker = Get-LastStallMarker $ServerLog
        } | ConvertTo-Json -Compress |
            Add-Content -Path $OutputPath -Encoding UTF8
        break
    }

    $cpuDelta = $null
    $cpuRate = $null
    if ($null -ne $previousCpu -and $null -ne $previousAt) {
        $elapsed = ($now - $previousAt).TotalSeconds
        if ($elapsed -gt 0) {
            $cpuDelta = [double]$process.CPU - [double]$previousCpu
            $cpuRate = $cpuDelta / $elapsed
        }
    }

    $udp = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object {
            $_.OwningProcess -eq $ProcessId -or $_.OwningProcess -eq 0
        } |
        Select-Object -First 1

    [ordered]@{
        at = $now.ToString("o")
        process_id = $ProcessId
        alive = $true
        cpu_seconds = [math]::Round([double]$process.CPU, 4)
        cpu_seconds_per_wall_second = (
            if ($null -eq $cpuRate) { $null }
            else { [math]::Round($cpuRate, 4) }
        )
        working_set_mb = [math]::Round($process.WorkingSet64 / 1MB, 2)
        private_mb = [math]::Round($process.PrivateMemorySize64 / 1MB, 2)
        thread_count = $process.Threads.Count
        responding = $process.Responding
        udp_port = $Port
        udp_bound = ($null -ne $udp)
        last_stall_marker = Get-LastStallMarker $ServerLog
    } | ConvertTo-Json -Compress |
        Add-Content -Path $OutputPath -Encoding UTF8

    $previousCpu = [double]$process.CPU
    $previousAt = $now

    Start-Sleep -Milliseconds $IntervalMs
}
