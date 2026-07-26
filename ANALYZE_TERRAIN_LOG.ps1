$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DefaultLog = Join-Path $env:APPDATA "Godot\app_userdata\Real Scale Procedural Moon\logs\terrain_performance.jsonl"
$LogPath = $DefaultLog
if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($args[0])) {
    $LogPath = $args[0]
}
if (-not (Test-Path $LogPath)) {
    throw "Terrain performance log was not found: $LogPath"
}

$Entries = @()
Get-Content $LogPath | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
        $Entries += ($_ | ConvertFrom-Json)
    } catch {
        Write-Warning "Skipped invalid JSONL line"
    }
}

function Percentile([double[]]$Values, [double]$Fraction) {
    if ($Values.Count -eq 0) { return 0.0 }
    $Sorted = @($Values | Sort-Object)
    $Index = [Math]::Min($Sorted.Count - 1, [Math]::Max(0, [Math]::Ceiling($Sorted.Count * $Fraction) - 1))
    return [double]$Sorted[$Index]
}

$CommitRows = @()
$Entries | Where-Object { $_.event -eq "terrain_commit_stage" } | Group-Object { $_.data.stage } | ForEach-Object {
    $Values = @($_.Group | ForEach-Object { [double]$_.data.duration_ms })
    $CommitRows += [PSCustomObject]@{
        Stage = $_.Name
        Count = $Values.Count
        AverageMs = [Math]::Round(($Values | Measure-Object -Average).Average, 2)
        P95Ms = [Math]::Round((Percentile $Values 0.95), 2)
        MaximumMs = [Math]::Round(($Values | Measure-Object -Maximum).Maximum, 2)
    }
}

$Background = @{}
$Entries | Where-Object { $_.event -eq "terrain_surface_swapped" } | ForEach-Object {
    $Map = $_.data.background_timings_ms
    if ($null -eq $Map) { return }
    $Map.PSObject.Properties | ForEach-Object {
        if (-not $Background.ContainsKey($_.Name)) { $Background[$_.Name] = @() }
        $Background[$_.Name] += [double]$_.Value
    }
}
$BackgroundRows = @()
foreach ($Name in $Background.Keys) {
    $Values = @($Background[$Name])
    $BackgroundRows += [PSCustomObject]@{
        Stage = $Name
        Count = $Values.Count
        AverageMs = [Math]::Round(($Values | Measure-Object -Average).Average, 2)
        P95Ms = [Math]::Round((Percentile $Values 0.95), 2)
        MaximumMs = [Math]::Round(($Values | Measure-Object -Maximum).Maximum, 2)
    }
}

$LongFrames = @($Entries | Where-Object { $_.event -eq "long_frame_detected" } | Sort-Object { [double]$_.data.frame_ms } -Descending | Select-Object -First 15)
$Swaps = @($Entries | Where-Object { $_.event -eq "terrain_surface_swapped" })
$SyncBuilds = @($Entries | Where-Object { $_.event -eq "synchronous_surface_rebuild" })

Write-Host ""
Write-Host "=== Terrain performance summary ==="
Write-Host "Log: $LogPath"
Write-Host "Entries: $($Entries.Count)  Swaps: $($Swaps.Count)  Long frames: $($LongFrames.Count)  Sync builds: $($SyncBuilds.Count)"
Write-Host ""
Write-Host "--- Background CPU stages ---"
$BackgroundRows | Sort-Object MaximumMs -Descending | Format-Table -AutoSize
Write-Host "--- Main-thread commit stages ---"
$CommitRows | Sort-Object MaximumMs -Descending | Format-Table -AutoSize
Write-Host "--- Longest frames ---"
$LongFrames | ForEach-Object {
    [PSCustomObject]@{
        FrameMs = [Math]::Round([double]$_.data.frame_ms, 2)
        State = $_.data.state
        CommitStage = $_.data.commit_stage
        ActiveCell = $_.data.active_cell_id
        TargetCell = $_.data.target_cell_id
    }
} | Format-Table -AutoSize

$ReportPath = Join-Path $ProjectRoot ("terrain-performance-summary-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$Lines = @()
$Lines += "Terrain performance summary"
$Lines += "Log: $LogPath"
$Lines += "Entries: $($Entries.Count); Swaps: $($Swaps.Count); Long frames: $($LongFrames.Count); Sync builds: $($SyncBuilds.Count)"
$Lines += ""
$Lines += "Background CPU stages:"
$Lines += ($BackgroundRows | Sort-Object MaximumMs -Descending | Format-Table -AutoSize | Out-String)
$Lines += "Main-thread commit stages:"
$Lines += ($CommitRows | Sort-Object MaximumMs -Descending | Format-Table -AutoSize | Out-String)
$Lines += "Longest frames:"
$Lines += ($LongFrames | ForEach-Object {
    "frame_ms=$([Math]::Round([double]$_.data.frame_ms, 2)); state=$($_.data.state); stage=$($_.data.commit_stage); active=$($_.data.active_cell_id); target=$($_.data.target_cell_id)"
})
$Lines | Set-Content -Encoding UTF8 $ReportPath
Write-Host "Summary written to: $ReportPath"
